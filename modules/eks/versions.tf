# eks 모듈 - versions.tf
# 모듈은 provider source 만 선언, 버전 고정은 루트(envs/dev)에서.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    # OIDC provider 의 지문 계산용(cicd 모듈과 동일 패턴).
    tls = {
      source = "hashicorp/tls"
    }
  }
}
