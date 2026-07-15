# edge 모듈 - acm.tf
#
# 인증서를 두 리전에 따로 만든다. 같은 도메인이라도 리전이 다르면 별개 인증서다.
#   서울(ap-northeast-2) → ALB 가 붙인다 (배포팀이 Ingress annotation 으로)
#   버지니아(us-east-1)  → CloudFront 가 붙인다 (CloudFront 는 us-east-1 인증서만 받는다)

# ── 서울: ALB 용 ──────────────────────────────────
resource "aws_acm_certificate" "alb" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = merge(var.tags, { Name = "${local.name_prefix}-acm-alb" })

  # 인증서 교체 시 새것을 먼저 만들고 옛것을 지운다(무중단).
  lifecycle {
    create_before_destroy = true
  }
}

# ── 버지니아: CloudFront 용 ────────────────────────
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.virginia

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = merge(var.tags, { Name = "${local.name_prefix}-acm-cloudfront" })

  lifecycle {
    create_before_destroy = true
  }
}

# ── DNS 검증 레코드 ───────────────────────────────
# AWS: "이 도메인이 네 것이면 우리가 준 CNAME 을 DNS 에 올려봐" → Terraform 이 자동 등록.
#
# ⚠️ 두 인증서(서울·버지니아)는 같은 도메인이라 AWS 가 요구하는 검증 CNAME 이 '동일하다'.
#    (AWS 문서: 같은 도메인으로 인증서를 여러 개 요청하면 CNAME 하나로 전부 검증된다)
#    그래서 레코드는 한 벌만 만들고 두 인증서가 함께 쓴다.
#    apex(myminiinfra.store)와 wildcard(*.myminiinfra.store)도 CNAME 이 같아
#    이름으로 묶어(...) 중복을 없앤다. 안 그러면 같은 레코드를 두 번 만들려다 깨진다.
locals {
  validation_records = {
    for dvo in tolist(aws_acm_certificate.cloudfront.domain_validation_options) :
    dvo.resource_record_name => {
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }...
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = local.validation_records

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.key
  type            = each.value[0].type
  records         = [each.value[0].record]
  ttl             = 60
  allow_overwrite = true
}

# ── 검증 완료까지 대기 ─────────────────────────────
# 레코드를 올린 뒤 AWS 가 인증서를 ISSUED 로 바꿀 때까지 기다린다(보통 1~3분).
resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.virginia

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}