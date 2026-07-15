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

# CloudFront 용 ACM 인증서는 us-east-1(버지니아)에서만 발급된다. CloudFront 만의 예외다.
# 그래서 두 번째 aws provider 를 alias 로 단다. edge 모듈이 이걸 주입받아 쓴다.
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"

  # alias provider 는 default_tags 를 물려받지 않는다. 여기도 똑같이 달아야 태그가 붙는다.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}