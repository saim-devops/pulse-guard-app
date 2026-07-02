terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # bucket / region / dynamodb_table are supplied at `terraform init` time:
  #   terraform init \
  #     -backend-config="bucket=<state bucket from bootstrap output>" \
  #     -backend-config="region=ap-south-1" \
  #     -backend-config="dynamodb_table=<lock table from bootstrap output>"
  backend "s3" {
    key     = "terraform.tfstate"
    encrypt = true
  }
}
