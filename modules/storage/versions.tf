# storage 모듈 - versions.tf
# 모듈은 provider source 만 선언, 버전 고정은 루트(envs/dev)에서.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
