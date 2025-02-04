# ------------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------------
locals {
  admin_cidrs  = values(data.vault_generic_secret.internal_cidrs.data)
  s3_releases  = data.vault_generic_secret.s3_releases.data
  xml_rds_data = data.vault_generic_secret.xml_rds_data.data
  xml_fe_data  = data.vault_generic_secret.xml_fe_data.data_json
  xml_bep_data = data.vault_generic_secret.xml_bep_data.data_json
  xml_ec2_data = data.vault_generic_secret.xml_ec2_data.data

  kms_keys_data          = data.vault_generic_secret.kms_keys.data
  security_kms_keys_data = data.vault_generic_secret.security_kms_keys.data
  logs_kms_key_id        = local.kms_keys_data["logs"]
  ssm_kms_key_id         = local.security_kms_keys_data["session-manager-kms-key-arn"]

  security_s3_data            = data.vault_generic_secret.security_s3_buckets.data
  session_manager_bucket_name = local.security_s3_data["session-manager-bucket-name"]

  internal_fqdn = format("%s.%s.aws.internal", split("-", var.aws_account)[1], split("-", var.aws_account)[0])

  rds_ingress_cidrs = concat(local.admin_cidrs, var.rds_onpremise_access)

  #For each log map passed, add an extra kv for the log group name
  fe_cw_logs  = { for log, map in var.fe_cw_logs : log => merge(map, { "log_group_name" = "${var.application}-fe-${log}" }) }
  bep_cw_logs = { for log, map in var.bep_cw_logs : log => merge(map, { "log_group_name" = "${var.application}-bep-${log}" }) }

  fe_log_groups  = compact([for log, map in local.fe_cw_logs : lookup(map, "log_group_name", "")])
  bep_log_groups = compact([for log, map in local.bep_cw_logs : lookup(map, "log_group_name", "")])

  xml_fe_ansible_inputs = {
    s3_bucket_releases         = local.s3_releases["release_bucket_name"]
    s3_bucket_configs          = local.s3_releases["config_bucket_name"]
    heritage_environment       = var.environment
    version                    = var.fe_app_release_version
    default_nfs_server_address = var.nfs_server
    mounts_parent_dir          = var.nfs_mount_destination_parent_dir
    mounts                     = var.nfs_mounts
    region                     = var.aws_region
    cw_log_files               = local.fe_cw_logs
    cw_agent_user              = "root"
  }

  xml_bep_ansible_inputs = {
    s3_bucket_releases         = local.s3_releases["release_bucket_name"]
    s3_bucket_configs          = local.s3_releases["config_bucket_name"]
    heritage_environment       = var.environment
    version                    = var.bep_app_release_version
    default_nfs_server_address = var.nfs_server
    mounts_parent_dir          = var.nfs_mount_destination_parent_dir
    mounts                     = var.nfs_mounts
    region                     = var.aws_region
    cw_log_files               = local.bep_cw_logs
    cw_agent_user              = "root"
  }

  websubnet_cidrs = [for subnet in data.aws_subnet.web_details : subnet.cidr_block]

  default_tags = {
    Terraform   = "true"
    Application = upper(var.application)
    Region      = var.aws_region
    Account     = var.aws_account
  }
}
