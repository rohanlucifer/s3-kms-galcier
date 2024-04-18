provider "aws" {
  region  = "eu-central-1"
}

module "s3-kms-glacier" {
  source = "./modules"
  s3_buckets = {
    bucket1 = {
      name                      = "s3-ing-test-glacier"
      ignore_public_acls        = true
      block_public_policy       = true
      restrict_public_buckets   = true
      kms_key_description       = "This is the key used for the s3-kms-glacier s3"
      kms_deletion_window_days  = 30
      kms_enable_key_rotation   = true
      kms_alias_name            = "aws/s3-kms-glacier"
    }
  }
}
module "secrets-manager-3" {

  source = "./modules"

  secrets = {
    secret-binary = {
      description             = "This is a binary secret"
      name                    = "secret-rohan"
      description             = "Another binary secret"
      secret_binary           = <<EOT
      "-----BEGIN OPENSSH PRIVATE KEY-----
-----END OPENSSH PRIVATE KEY-----"
EOT
      recovery_window_in_days = 0
      tags = {
        app = "web"
      }
    }
  }

  tags = {
    Owner       = "DevOps team"
    Environment = "dev"
    Terraform   = true
  }
}
/*
module "secret_manager" {
 source = "./modules"
 secret_name = "nibasss"
 secret_string = ""
}
*/
output "s3-bucket" {
 value = module.s3-kms-glacier
}

output "secret_arn" {
 value = module.secrets-manager-3
}
