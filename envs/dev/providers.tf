# envs/dev - providers.tf
# 이 환경(dev)이 실제로 쓰는 provider 설정. 리전과 공통 태그를 여기서 못박는다.
provider "aws" {
  region = var.aws_region

  # default_tags: 이 provider 로 만드는 '모든' 리소스에 자동으로 붙는 태그.
  #   → 리소스마다 일일이 안 달아도 비용 배분·OpenCost 판별(FinOps)이 된다.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
