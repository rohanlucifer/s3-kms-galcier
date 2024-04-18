# Define a map variable for bucket configurations
variable "s3_buckets" {
  type = map(object({
    name                    = string
    #tags                    = map(string)
    #object_ownership        = string
    block_public_policy     = bool
    ignore_public_acls      = bool
    restrict_public_buckets = bool
  #  acl                     = string
    #versioning              = string
    kms_key_description     = string
    kms_deletion_window_days = number
    kms_enable_key_rotation = bool
    kms_alias_name          = string
    #aws_account_id          = string
  }))
  default = {}
}

# Create S3 buckets directly from the s3_buckets map
resource "aws_s3_bucket" "buckets" {
  for_each = var.s3_buckets

  bucket = each.value.name
  #tags   = each.value.tags
}

# Loop through the s3_buckets map to create other resources for each bucket
resource "aws_s3_bucket_ownership_controls" "ownership_controls" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.buckets[each.key].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "access_blocks" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = true
  block_public_policy     = each.value.block_public_policy
  ignore_public_acls      = each.value.ignore_public_acls
  restrict_public_buckets = each.value.restrict_public_buckets
}
/*
resource "aws_s3_bucket_acl" "bucket_acls" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.buckets[each.key].id
  acl    = each.value.acl
}
*/
resource "aws_s3_bucket_versioning" "versionings" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "kms_keys" {
  for_each = var.s3_buckets

  description             = each.value.kms_key_description
  deletion_window_in_days = each.value.kms_deletion_window_days
  enable_key_rotation     = each.value.kms_enable_key_rotation
  #tags                    = each.value.tags
}
/*
resource "aws_kms_key_policy" "kms_key_policies" {
  for_each = var.s3_buckets

  key_id = aws_kms_key.kms_keys[each.key].id
  policy = data.aws_iam_policy_document.kms_policy[each.key].json
}
*/
resource "aws_kms_alias" "kms_aliases" {
  for_each = var.s3_buckets
  #name          = each.value.name
#  name          = "s3/${each.value.name}"
   name          = "alias/${each.value.name}-kms"
  #name          = "${aws_kms_key.kms_keys[each.key].arn}/${each.value.kms_alias_name}"
  target_key_id = aws_kms_key.kms_keys[each.key].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_bucket_encryptions" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.kms_keys[each.key].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_kms_key_policy" "kms_key_policies" {
  for_each = var.s3_buckets

  key_id = aws_kms_key.kms_keys[each.key].id
  policy = jsonencode({
    "Version": "2012-10-17",
    "Id": "default",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
           "AWS": "*"
        },
        "Action": "kms:*",
        "Resource": "*"
      }
    ]
  })
}


/*
# Define IAM policy document data source
data "aws_iam_policy_document" "kms_policy" {
  for_each = var.s3_buckets

  version = "2012-10-17"

  statement {
    effect = "Allow"
    actions = ["kms:*"]
    principals {
      type = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_kms_key.kms_keys[each.key].arn]
  }
}
*/
# Outputs
output "s3_bucket_name" {
  value = {
    for key, bucket in aws_s3_bucket.buckets : key => bucket.id
  }
}

output "kms_key_id" {
  value = {
    for key, kms_key in aws_kms_key.kms_keys : key => kms_key.id
  }
}


## s3-lifecyecle-policy
resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  rule {
    id      = "log"
    status  = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  bucket = "s3-ing-test-glacier"
}

resource "aws_secretsmanager_secret" "sm" {
  for_each                       = var.secrets
  name                           = lookup(each.value, "name_prefix", null) == null && lookup(each.value, "name", null) == null ? each.key : (lookup(each.value, "name_prefix", null) == null && lookup(each.value, "name", null) != null ? each.value.name : null)
  name_prefix                    = lookup(each.value, "name_prefix", null) != null ? lookup(each.value, "name_prefix") : null
  description                    = lookup(each.value, "description", null)
  kms_key_id                     = lookup(each.value, "kms_key_id", null)
  policy                         = lookup(each.value, "policy", null)
  force_overwrite_replica_secret = lookup(each.value, "force_overwrite_replica_secret", false)
  recovery_window_in_days        = lookup(each.value, "recovery_window_in_days", var.recovery_window_in_days)
  tags                           = merge(var.tags, lookup(each.value, "tags", null))
  dynamic "replica" {
    for_each = lookup(each.value, "replica_regions", {})
    content {
      region     = try(replica.value.region, replica.key)
      kms_key_id = try(replica.value.kms_key_id, null)
    }
  }
}
resource "aws_secretsmanager_secret_version" "sm-svu" {
  for_each       = { for k, v in var.secrets : k => v if var.unmanaged }
  secret_id      = aws_secretsmanager_secret.sm[each.key].arn
  secret_string  = lookup(each.value, "secret_string", null) != null ? lookup(each.value, "secret_string") : (lookup(each.value, "secret_key_value", null) != null ? jsonencode(lookup(each.value, "secret_key_value", {})) : null)
  secret_binary  = lookup(each.value, "secret_binary", null) != null ? base64encode(lookup(each.value, "secret_binary")) : null
  version_stages = var.version_stages
  depends_on     = [aws_secretsmanager_secret.sm]

  lifecycle {
    ignore_changes = [
      secret_string,
      secret_binary,
      secret_id,
    ]
  }
}

## variables
variable "unmanaged" {
  description = "Terraform must ignore secrets lifecycle. Using this option you can initialize the secrets and rotate them outside Terraform, thus, avoiding other users to change or rotate the secrets by subsequent runs of Terraform"
  type        = bool
  default     = false
}
variable "version_stages" {
  description = "List of version stages to be handled. Kept as null for backwards compatibility."
  type        = list(string)
  default     = null
}

variable "secrets" {
  description = "Map of secrets to keep in AWS Secrets Manager"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Specifies a key-value map of user-defined tags that are attached to the secret."
  type        = any
  default     = {}
}
variable "recovery_window_in_days" {
  description = "Specifies the number of days that AWS Secrets Manager waits before it can delete the secret. This value can be 0 to force deletion without recovery or range from 7 to 30 days."
  type        = number
  default     = 0
}
#outputs
output "secret_arns" {
  description = "Secrets arns map"
  value       = { for k, v in aws_secretsmanager_secret.sm : k => v["arn"] }
}
/*
# variable "certFileAndPath" {
#  default = "/home/berrybytes/devops/s3-kms-glacier/modules/test"
#}

resource "aws_secretsmanager_secret" "example-certss" {
  name                  = var.secret_name
  recovery_window_in_days = 0
}

#resource "aws_secretsmanager_secret_version" "cert-val" {
 # secret_id     = aws_secretsmanager_secret.example-certss.id
  #secret_binary = filebase64(var.certFileAndPath)
#}
resource "aws_secretsmanager_secret_version" "cert-val" {
  secret_id     = aws_secretsmanager_secret.example-certss.id
  secret_string = var.secret_string
  #secret_string = <<-EOT
}

output "secret_arn" {
  value = aws_secretsmanager_secret.example-certss.arn
}


variable "secret_name" {
  description = "Name of the AWS Secrets Manager secret"
  default     = "nibasss"
}

variable "secret_string" {
  description = "Value of the secret"
  type        = string
  sensitive = true
  default = <<EOT
  -----BEGIN OPENSSH PRIVATE KEY-----
-----END OPENSSH PRIVATE KEY-----
  EOT
}
*/
