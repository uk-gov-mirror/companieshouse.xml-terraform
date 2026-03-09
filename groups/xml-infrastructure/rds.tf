# ------------------------------------------------------------------------------
# RDS Security Group and rules
# ------------------------------------------------------------------------------
module "xml_rds_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name        = "sgr-${var.application}-rds-001"
  description = "Security group for the ${var.application} rds database"
  vpc_id      = data.aws_vpc.vpc.id

  ingress_with_source_security_group_id = local.rds_ingress_from_services

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "oracle-db-tcp"
      source_security_group_id = module.xml_fe_asg_security_group.security_group_id
      description              = "Allow frontends to connect to RDS"
    },
    {
      rule                     = "oracle-db-tcp"
      source_security_group_id = module.xml_bep_asg_security_group.security_group_id
      description              = "Allow backend to connect to RDS"
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 2

  egress_rules = ["all-all"]
}

resource "aws_security_group_rule" "rds_cloud_ingress" {
  for_each = var.rds_cloud_access

  description       = "Ingress access from ${each.key}"
  type              = "ingress"
  from_port         = 1521
  to_port           = 1521
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = module.xml_rds_security_group.security_group_id
}

resource "aws_security_group_rule" "dba_dev_ingress" {
  for_each = toset(local.dba_dev_cidrs_list)

  type              = "ingress"
  from_port         = 1521
  to_port           = 1521
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = module.xml_rds_security_group.security_group_id
}

resource "aws_security_group_rule" "concourse_ingress" {
  count = var.rds_concourse_access ? 1 : 0

  description       = "Ingress from Concourse"
  type              = "ingress"
  from_port         = 1521
  to_port           = 1521
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.concourse.id]
  security_group_id = module.xml_rds_security_group.security_group_id
}

resource "aws_security_group_rule" "admin_ingress_db" {

  description       = "Permit Oracle DB access from admin prefix list"
  type              = "ingress"
  from_port         = 1521
  to_port           = 1521
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.admin.id]
  security_group_id = module.xml_rds_security_group.security_group_id
}

resource "aws_security_group_rule" "admin_ingress_oem" {

  description       = "Permit Oracle Enterprise Manager access from admin prefix list"
  type              = "ingress"
  from_port         = 5500
  to_port           = 5500
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.admin.id]
  security_group_id = module.xml_rds_security_group.security_group_id
}

resource "aws_security_group_rule" "test_concourse_ingress_db" {
  count = var.test_concourse_rds_access_enable ? 1 : 0

  description       = "Ingress from test Concourse"
  type              = "ingress"
  from_port         = 1521
  to_port           = 1521
  protocol          = "tcp"
  cidr_blocks       = local.test_concourse_cidrs
  security_group_id = module.xml_rds_security_group.security_group_id
}

resource "aws_security_group_rule" "test_concourse_ingress_oem" {
  count = var.test_concourse_rds_access_enable ? 1 : 0

  description       = "Permit Oracle Enterprise Manager access from test Concourse"
  type              = "ingress"
  from_port         = 5500
  to_port           = 5500
  protocol          = "tcp"
  cidr_blocks       = local.test_concourse_cidrs
  security_group_id = module.xml_rds_security_group.security_group_id
}

# ------------------------------------------------------------------------------
# RDS xml
# ------------------------------------------------------------------------------
module "xml_rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.13.1"

  create_db_parameter_group = "true"
  create_db_subnet_group    = "true"

  identifier                 = join("-", ["rds", var.application, var.environment, "001"])
  engine                     = "oracle-se2"
  major_engine_version       = var.major_engine_version
  engine_version             = var.engine_version
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  license_model              = var.license_model
  instance_class             = var.instance_class
  allocated_storage          = var.allocated_storage
  multi_az                   = var.multi_az
  storage_encrypted          = true
  kms_key_id                 = data.aws_kms_key.rds.arn

  db_name  = upper(var.application)
  username = local.xml_rds_data["admin-username"]
  password = local.xml_rds_data["admin-password"]
  port     = "1521"

  manage_master_user_password = false

  deletion_protection              = true
  maintenance_window               = var.rds_maintenance_window
  backup_window                    = var.rds_backup_window
  backup_retention_period          = var.backup_retention_period
  skip_final_snapshot              = "false"
  final_snapshot_identifier_prefix = "${var.application}-final-deletion-snapshot"
  publicly_accessible              = false

  # Enhanced Monitoring
  monitoring_interval             = "30"
  monitoring_role_arn             = data.aws_iam_role.rds_enhanced_monitoring.arn
  enabled_cloudwatch_logs_exports = var.rds_log_exports

  performance_insights_enabled          = var.environment == "live" ? true : false
  performance_insights_kms_key_id       = data.aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  ca_cert_identifier = "rds-ca-rsa2048-g1"

  option_group_description    = "Option group for ${join("-", ["rds", var.application, var.environment, "001"])}"
  parameter_group_description = "Database parameter group for ${join("-", ["rds", var.application, var.environment, "001"])}"

  # RDS Security Group
  vpc_security_group_ids = [
    module.xml_rds_security_group.security_group_id,
    data.aws_security_group.rds_shared.id
  ]

  # DB subnet group
  subnet_ids = data.aws_subnets.data.ids

  # DB Parameter group
  family = join("-", ["oracle-se2", var.major_engine_version])

  parameters = var.parameter_group_settings

  options = concat([
    {
      option_name                    = "OEM"
      port                           = "5500"
      vpc_security_group_memberships = [module.xml_rds_security_group.security_group_id]
    }
  ], var.option_group_settings)

  timeouts = {
    "create" : "80m",
    "delete" : "80m",
    "update" : "80m"
  }

  tags = merge(
    local.default_tags,
    {
      Name        = join("-", ["rds", var.application, var.environment, "001"])
      ServiceTeam = "${upper(var.application)}-DBA-Support"
    }
  )
}

module "rds_start_stop_schedule" {
  source = "git@github.com:companieshouse/terraform-modules//aws/rds_start_stop_schedule?ref=tags/1.0.363"

  rds_schedule_enable = var.rds_schedule_enable

  rds_instance_id    = module.xml_rds.db_instance_identifier
  rds_start_schedule = var.rds_start_schedule
  rds_stop_schedule  = var.rds_stop_schedule
}

module "rds_cloudwatch_alarms" {
  source = "git@github.com:companieshouse/terraform-modules//aws/oracledb_cloudwatch_alarms?ref=tags/1.0.195"

  db_instance_id        = module.xml_rds.db_instance_identifier
  db_instance_shortname = upper(var.application)
  alarm_actions_enabled = var.alarm_actions_enabled
  alarm_name_prefix     = "Oracle RDS"
  alarm_topic_name      = var.alarm_topic_name
  alarm_topic_name_ooh  = var.alarm_topic_name_ooh
}
