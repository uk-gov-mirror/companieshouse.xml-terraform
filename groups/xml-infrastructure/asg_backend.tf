# ------------------------------------------------------------------------------
# XML Security Group and rules
# ------------------------------------------------------------------------------
module "xml_bep_asg_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "sgr-${var.application}-bep-asg-001"
  description = "Security group for the ${var.application} backend asg"
  vpc_id      = data.aws_vpc.vpc.id

  egress_rules = ["all-all"]
}

resource "aws_cloudwatch_log_group" "xml_bep" {
  name              = "logs-${var.application}-backend"
  retention_in_days = var.bep_log_group_retention_in_days

  tags = merge(
    local.default_tags,
    map(
      "ServiceTeam", "${upper(var.application)}-FE-Support"
    )
  )
}

# ASG Module
module "bep_asg" {
  source = "git@github.com:companieshouse/terraform-modules//aws/terraform-aws-autoscaling?ref=tags/1.0.36"

  name = "${var.application}-bep"
  # Launch configuration
  lc_name         = "${var.application}-bep-launchconfig"
  image_id        = data.aws_ami.bep_xml.id
  instance_type   = var.bep_instance_size
  security_groups = [module.xml_bep_asg_security_group.this_security_group_id]
  root_block_device = [
    {
      volume_size = "40"
      volume_type = "gp2"
      encrypted   = true
    },
  ]
  # Auto scaling group
  asg_name                       = "${var.application}-bep-asg"
  vpc_zone_identifier            = data.aws_subnet_ids.application.ids
  health_check_type              = "EC2"
  min_size                       = var.bep_min_size
  max_size                       = var.bep_max_size
  desired_capacity               = var.bep_desired_capacity
  health_check_grace_period      = 300
  wait_for_capacity_timeout      = 0
  force_delete                   = true
  enable_instance_refresh        = true
  refresh_min_healthy_percentage = 50
  refresh_triggers               = ["launch_configuration"]
  key_name                       = aws_key_pair.xml_keypair.key_name
  termination_policies           = ["OldestLaunchConfiguration"]
  iam_instance_profile           = module.xml_bep_profile.aws_iam_instance_profile.name
  user_data_base64               = data.template_cloudinit_config.bep_userdata_config.rendered

  tags_as_map = merge(
    local.default_tags,
    map(
      "ServiceTeam", "${upper(var.application)}-FE-Support"
    )
  )
}
