# eks 모듈 - sg_alb_cloudfront.tf
#
# ALB 인바운드를 CloudFront 오리진 IP 대역으로만 제한한다(B안 · 팀 결정 2026-08-13).
# ALB 자체는 Terraform 이 아니라 ALB Controller 가 런타임에 만들므로(§3-2 A 부류),
# 여기서는 SG 만 만들고 배포팀이 Ingress annotation(alb.ingress.kubernetes.io/security-groups)으로 붙인다.
#
# 프리픽스 리스트 ID 를 하드코딩하지 않고 이름으로 조회한다.
# AWS 관리형 리스트라 이름은 고정이고 ID 는 계정마다 같지 않을 수 있다.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb_cloudfront_only" {
  name        = "${local.name_prefix}-sg-alb-cloudfront"
  description = "ALB inbound restricted to CloudFront origin-facing IPs only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-sg-alb-cloudfront"
  })
}

# 매니페스트 Ingress 리스너는 443(HTTPS) 하나뿐이다(apps/*/ingress.yaml 의 listen-ports).
resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb_cloudfront_only.id
  description       = "HTTPS from CloudFront origin-facing prefix list"

  prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
  from_port      = 443
  to_port        = 443
  ip_protocol    = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb_cloudfront_only.id
  description       = "all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
