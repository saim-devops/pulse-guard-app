provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Aliased provider for us-east-1
# Required for CloudFront ACM certificates
provider "aws" {
  alias  = "use1"
  region = "us-east-1"    #fixed_can't change

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Auto-discover available Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}
