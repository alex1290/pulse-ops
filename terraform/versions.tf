terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 練習初期先用 local state；要多人協作或搭配 CI 時改成 S3 backend
  # backend "s3" {
  #   bucket       = "pulse-ops-tfstate-<your-account-id>"
  #   key          = "pulse-ops/terraform.tfstate"
  #   region       = "ap-northeast-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
