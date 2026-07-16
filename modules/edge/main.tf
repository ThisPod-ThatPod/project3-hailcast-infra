# edge 모듈 - main.tf

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # ALB 주소가 들어왔을 때만 CloudFront·레코드를 만든다.
  cloudfront_enabled = var.alb_dns_name != ""

  # CloudFront 가 오리진으로 부를 주소. ALB 의 AWS 자동 주소를 직접 안 쓰는 이유는 cloudfront.tf 참고.
  origin_domain = "origin.${var.domain_name}"
}

# 호스팅 영역은 Terraform 이 만들지 않고 '이미 있는 것'을 참조한다.
#   이유: destroy 할 때마다 영역이 지워지면 NS 4개가 바뀌고 위임을 매번 다시 등록해야 한다.
#   DNS 영역은 오래 사는 자원, 앱 인프라는 자주 지웠다 만드는 자원이라 수명주기가 달라 분리한다.
#
# domain_name 은 서브도메인(hailcast.myminiinfra.store)이고 그 이름의 영역이 이 계정에 따로 있다.
# 부모 도메인(myminiinfra.store)은 다른 계정에 있어서, 부모 영역에 NS 위임 레코드를 넣어야
# 이 영역이 해석된다. 그 위임이 살아 있기 전에 enable_edge 를 켜면 ACM 검증이 타임아웃까지
# 기다리다 실패한다. 위임은 부모 계정 주인이 수동으로 넣는다. terraform 이 못 한다.
data "aws_route53_zone" "this" {
  name         = "${var.domain_name}."
  private_zone = false
}