module "secrets-manager-3" {

  source = "./modules"

  secrets = {
    secret-binary = {
      description             = "This is a binary secret"
      name                    = "secret-binaries"
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

