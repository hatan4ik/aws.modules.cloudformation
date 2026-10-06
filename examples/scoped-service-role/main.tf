provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # The names artifacts.yaml gives its two resources, as ARNs. The template
  # derives both from the stack name, so the role can be scoped before the
  # stack exists.
  bucket_arn           = "arn:${local.partition}:s3:::${var.name}-${local.account_id}-${var.region}"
  parameter_arn_prefix = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/${var.name}/"
}

# Step 1: the service role, with exactly what artifacts.yaml needs. The
# actions come from the handlers of each resource type's registry schema
# (aws cloudformation describe-type --type RESOURCE --type-name <type>),
# limited to the properties the template sets, on the two resources only.
module "cloudformation_role" {
  source = "../../modules/service-role"

  name       = "cloudformation-${var.name}"
  path       = "/cloudformation/"
  account_id = local.account_id

  statements = {
    ArtifactsBucket = {
      actions = [
        # Create and delete, and the properties the template sets.
        "s3:CreateBucket", "s3:DeleteBucket",
        "s3:PutEncryptionConfiguration", "s3:PutBucketPublicAccessBlock", "s3:PutBucketVersioning",
        # Stack tags (including the module's Name) propagate to the bucket.
        "s3:PutBucketTagging", "s3:TagResource", "s3:UntagResource",
        # The handler reads the whole bucket configuration back after every
        # create and update, whichever properties the template sets.
        "s3:GetAccelerateConfiguration", "s3:GetAnalyticsConfiguration", "s3:GetBucketAbac", "s3:GetBucketAcl",
        "s3:GetBucketCORS", "s3:GetBucketLogging", "s3:GetBucketMetadataTableConfiguration",
        "s3:GetBucketNotification", "s3:GetBucketObjectLockConfiguration", "s3:GetBucketOwnershipControls",
        "s3:GetBucketPublicAccessBlock", "s3:GetBucketTagging", "s3:GetBucketVersioning", "s3:GetBucketWebsite",
        "s3:GetEncryptionConfiguration", "s3:GetIntelligentTieringConfiguration", "s3:GetInventoryConfiguration",
        "s3:GetLifecycleConfiguration", "s3:GetMetricsConfiguration", "s3:GetReplicationConfiguration",
        "s3:ListBucket", "s3:ListTagsForResource",
      ]
      resources = [local.bucket_arn]
    }

    BucketNameParameter = {
      actions = [
        "ssm:PutParameter", "ssm:GetParameters", "ssm:DeleteParameter",
        "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource",
      ]
      resources = ["${local.parameter_arn_prefix}*"]
    }
  }

  tags = { Example = "scoped-service-role" }
}

# Step 2: the stack, operated by that role. role_arn depends on the role's
# policies too, so the stack is created after its permissions exist and
# deleted before they are removed.
module "artifacts" {
  source = "../../"

  name         = var.name
  template     = { body = file("${path.module}/artifacts.yaml") }
  iam_role_arn = module.cloudformation_role.role_arn

  # Stack events, including an AccessDenied from a statement the template
  # outgrew, go to a topic someone watches.
  notification_arns = [var.notification_topic_arn]

  tags = { Example = "scoped-service-role" }
}
