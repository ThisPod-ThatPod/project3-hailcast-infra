# envs/dev - backend.tf
#
# tfstate 를 담는 S3 버킷. Terraform 이 스스로 못 만드는 '닭-달걀' 이라
# 이 버킷만 CLI 로 부트스트랩하고(버저닝·암호화·퍼블릭차단), 그 이름을 여기 박는다.
#   - 버저닝: tfstate 가 깨졌을 때 되돌릴 유일한 수단
#   - 암호화: 상태 파일엔 시크릿이 평문으로 들어간다
#   - use_lockfile: S3 자체 잠금으로 동시 apply 방지 (DynamoDB 불필요 · Terraform 1.11+)
terraform {
  backend "s3" {
    bucket       = "hailcast-dev-tfstate-7dde"
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}