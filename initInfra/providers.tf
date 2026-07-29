locals {
  clouds_yaml  = yamldecode(file(var.clouds_yaml_path))
  cloud_config = local.clouds_yaml["clouds"][var.cloud_name]
  auth         = local.cloud_config["auth"]
}

provider "openstack" {
  auth_url                      = local.auth["auth_url"]
  application_credential_id     = local.auth["application_credential_id"]
  application_credential_secret = local.auth["application_credential_secret"]
  region                        = try(local.cloud_config["region_name"], null)
  endpoint_type                 = try(local.cloud_config["interface"], "public")
}
