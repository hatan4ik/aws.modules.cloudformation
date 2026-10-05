locals {
  # The module adds only a Name tag, and a caller's Name wins.
  tags = merge({ Name = var.name }, var.tags)

  # Inputs of the advisory checks in checks.tf; see docs/DESIGN.md D14 and D16.

  # Amazon S3 object URL hosts: virtual-hosted (<bucket>.s3.<region>.
  # amazonaws.com, legacy <bucket>.s3.amazonaws.com and s3-<region>), path
  # style (s3.<region>.amazonaws.com/<bucket>/...), dualstack and FIPS
  # endpoints, GovCloud (same suffix), and China (amazonaws.com.cn). The same
  # host pattern the url validations accept.
  s3_url_pattern = "^https://([a-z0-9][a-z0-9.-]*\\.)?s3([.-][a-z0-9-]+)*\\.amazonaws\\.com(\\.cn)?/"
  # An S3 object version pinned in the query string.
  s3_version_id_pattern = "[?&]versionId=[^&#]+"

  template_url_unpinned     = var.template.url == null ? false : can(regex(local.s3_url_pattern, var.template.url)) && !can(regex(local.s3_version_id_pattern, var.template.url))
  stack_policy_url_unpinned = try(var.stack_policy.url, null) == null ? false : can(regex(local.s3_url_pattern, var.stack_policy.url)) && !can(regex(local.s3_version_id_pattern, var.stack_policy.url))

  # yamldecode rejects every CloudFormation short-form intrinsic (!Ref,
  # !GetAtt, !Sub, ...) as an unsupported tag, on every Terraform version
  # this module supports. A local tag is ! then a name, at the start of a
  # node, so removing it (and keeping the character before it) leaves the
  # tagged value as plain YAML. !!-prefixed standard tags are kept.
  cfn_short_form_tag_pattern = "/(^|[\\s\\[{,])![A-Za-z][A-Za-z0-9:]*/"

  # A template is a JSON or YAML mapping. The provider already rejects a body
  # that is not valid JSON or YAML at plan; it accepts any other document,
  # such as a bare string (a file path passed without file()) or a list,
  # which can never be a template and fails only at apply.
  template_body_not_a_mapping = var.template.body == null ? false : !(
    can(keys(jsondecode(var.template.body))) ||
    can(keys(yamldecode(replace(var.template.body, local.cfn_short_form_tag_pattern, "$1"))))
  )
}
