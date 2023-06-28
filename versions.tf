terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0.0"
    }
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = "update_access_key"
  secret_key = "update_secret_key"
}
