# edge 모듈 - versions.tf
# 모듈은 provider source 만 선언, 버전 고정은 루트(envs/dev)에서.
#
# configuration_aliases: "이 모듈은 aws.virginia 라는 두 번째 aws provider 를 요구한다"는 선언.
#   CloudFront 인증서는 us-east-1 에서만 발급되기 때문에 provider 가 두 개 필요하다.
#   모듈은 provider 를 스스로 만들지 않는다. 루트가 주입한다.
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.virginia]
    }
  }
}