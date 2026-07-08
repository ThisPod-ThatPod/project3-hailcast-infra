# envs/dev - versions.tf
# 루트가 provider '버전'을 한 곳에서 고정한다(모듈은 source 만 선언).
#   - aws    : 대부분의 인프라
#   - random : data 모듈이 RDS 비밀번호를 무작위 생성하는 데 사용
#   - tls    : cicd 모듈이 GitHub OIDC 인증서 지문을 계산하는 데 사용
terraform {
  required_version = ">=1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
