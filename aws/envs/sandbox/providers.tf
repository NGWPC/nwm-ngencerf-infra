provider "aws" {
  region = "us-east-1"

  # Single source of tags (local.common_tags in main.tf), used here for every
  # aws-provider resource AND passed to the module as var.tags so the awscc PCS
  # resources (which ignore default_tags) carry the identical set, including the
  # Team tag the Sandbox account enforces via SCP.
  default_tags {
    tags = local.common_tags
  }
}

# awscc (AWS Cloud Control) provider — hosts the AWS PCS resources in pcs.tf.
# No default_tags support; PCS resources tag themselves where the schema
# allows. Region must match the aws provider.
provider "awscc" {
  region = "us-east-1"
}
