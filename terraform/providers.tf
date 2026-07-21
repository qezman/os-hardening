terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# scoped "project2" CLI profile so it never
# runs against a different AWS identity/acct
provider "aws" {
  region  = var.aws_region
  profile = "project2"
}
