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
