# rds 서브모듈 - versions.tf
# 모듈은 provider 의 'source'만 선언한다. 버전 고정(required_version·version)은
# 루트(envs/dev)에서 한 곳으로 관리한다 → 모듈 재사용 시 버전 충돌을 막는다.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
