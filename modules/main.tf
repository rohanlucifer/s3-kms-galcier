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
variable "certFileAndPath" {
  default = "/home/berrybytes/devops/s3-kms-glacier/modules/test"
}

resource "aws_secretsmanager_secret" "example-certss" {
  name                  = var.secret_name
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "cert-val" {
  secret_id     = aws_secretsmanager_secret.example-certss.id
  secret_binary = filebase64(var.certFileAndPath)
}

output "secret_arn" {
  value = aws_secretsmanager_secret.example-certss.arn
}


variable "secret_name" {
  description = "Name of the AWS Secrets Manager secret"
  default     = "testing/private"
}
