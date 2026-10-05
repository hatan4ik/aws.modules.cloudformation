provider "aws" {
  region = var.region
}

# A vendor or AWS Marketplace solution delivered as a template in S3. The URL
# should pin the object version (?versionId=...), so the same plan always
# deploys the same template and a new template is a visible change to the
# URL; without it, check.template_url_not_version_pinned warns.
module "marketplace_solution" {
  source = "../../"

  name     = var.name
  template = { url = var.template_url }

  parameters = var.parameters

  # The vendor template creates named IAM roles; acknowledging that is an
  # explicit, reviewable decision.
  capabilities = ["CAPABILITY_NAMED_IAM"]

  iam_role_arn = var.cloudformation_role_arn

  # A failed first create deletes the stack instead of leaving it in
  # ROLLBACK_COMPLETE, so the next apply simply retries the create. The stack
  # events stay readable by stack ID for 90 days.
  on_failure = "DELETE"

  # CloudFormation gives up on creation after an hour; Terraform waits a
  # little longer so the CloudFormation-side failure is what gets reported.
  timeout_in_minutes = 60
  timeouts           = { create = "70m", update = "70m", delete = "60m" }

  notification_arns = var.notification_topic_arn == null ? [] : [var.notification_topic_arn]

  tags = {
    Environment = "example"
    Vendor      = "example-vendor"
  }
}
