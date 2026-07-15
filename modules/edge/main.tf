# edge 모듈 - main.tf

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # ALB 주소가 들어왔을 때만 CloudFront·레코드를 만든다.
  cloudfront_enabled = var.alb_dns_name != ""

  # CloudFront 가 오리진으로 부를 주소. ALB 의 AWS 자동 주소를 직접 안 쓰는 이유는 cloudfront.tf 참고.
  origin_domain = "origin.${var.domain_name}"
}

# 호스팅 영역은 Terraform 이 만들지 않고 '이미 있는 것'을 참조한다.
#   이유: destroy 할 때마다 영역이 지워지면 NS 4개가 바뀌고, 가비아에 매번 다시 등록해야 한다.
#   DNS 영역은 오래 사는 자원, 앱 인프라는 자주 지웠다 만드는 자원 — 수명주기가 달라 분리한다.
data "aws_route53_zone" "this" {
  name         = "${var.domain_name}."
  private_zone = false
}