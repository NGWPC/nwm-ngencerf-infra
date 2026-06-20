provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "ngencerf"
      ManagedBy   = "Terraform"
      Repo        = "nwm-ngencerf-infra"
      Team        = "nwm"
      POC         = "Miguel Pena"
      Owner       = var.owner
      Environment = "test-integration"
    }
  }
}

# awscc (AWS Cloud Control) provider: hosts the AWS PCS resources in pcs.tf.
# The awscc provider does not support the aws provider's default_tags, so the
# PCS resources are tagged via an explicit tags input passed to the module.
# Region must match the aws provider.
provider "awscc" {
  region = "us-east-1"
}
