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

# awscc (AWS Cloud Control) provider — hosts the AWS PCS resources in pcs.tf.
# No default_tags support; PCS resources tag themselves where the schema
# allows. Region must match the aws provider.
provider "awscc" {
  region = "us-east-1"
}
