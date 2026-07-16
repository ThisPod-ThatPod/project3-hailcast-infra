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
# ⭐ 레코드는 '하나' 면 된다. 겹치는 게 두 겹이다.
#   ① apex(myminiinfra.store)와 wildcard(*.myminiinfra.store)의 검증 CNAME 이 같다.
#      AWS 문서(ACM · dns-validation): 와일드카드 도메인의 검증 문자열은 기반 도메인의 것과 동일하다.
#   ② 서울·버지니아 인증서의 검증 CNAME 도 같다. 같은 계정·같은 도메인이면 리전이 달라도 같다.
#      AWS 문서(같은 페이지): CNAME 검증 토큰은 어느 리전에서나 통한다.
#   → 검증 항목은 4개(인증서2 × 도메인2)지만 실제 레코드는 1개다. for_each 를 쓸 이유가 없다.
#
# ⚠️ for_each 를 쓰면 안 되는 이유 (2026-07-16 · 이미선 리뷰 지적 · 옛 코드의 버그).
#   for_each 는 '키' 가 plan 시점에 known 이어야 한다. '값' 은 unknown 이어도 된다.
#   resource_record_name 은 ACM 이 인증서를 발급한 뒤에야 정해져서 최초 apply 의 plan 에선
#   (known after apply) 다. 그걸 키로 쓰면 plan 이 "Invalid for_each argument" 로 멈춘다.
#   ※ terraform validate 는 이걸 못 잡는다 — plan 단계 검사다. validate Success 는 근거가 못 된다.
#
# ⚠️ 전제: SAN 이 apex + wildcard 뿐일 때만 성립한다.
#   나중에 SAN 에 다른 이름(예: api.myminiinfra.store)을 더하면 그 도메인은 '다른 CNAME' 을 받아
#   레코드 하나로는 모자란다. 그때는 for_each 로 가되 키를 dvo.domain_name 으로 둔다
#   (domain_name 은 var 에서 오므로 plan 시점 known — AWS provider 공식 문서 패턴).
locals {
  # tolist()[0] — set 이라 순서가 보장되지 않지만(provider issue #8531),
  # 두 원소(apex·wildcard)의 record 필드가 '동일' 하므로 어느 쪽이 잡혀도 결과가 같다.
  # 위 '전제' 가 깨지는 순간 이 [0] 도 함께 깨진다. 세트로 묶어서 본다.
  validation = tolist(aws_acm_certificate.cloudfront.domain_validation_options)[0]
}

resource "aws_route53_record" "acm_validation" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.validation.resource_record_name
  type    = local.validation.resource_record_type
  records = [local.validation.resource_record_value]
  ttl     = 60

  # destroy 후 재생성 때 같은 이름의 잔존 레코드가 있으면 덮어쓰고 지나간다.
  allow_overwrite = true
}

# ── 검증 완료까지 대기 ─────────────────────────────
# 레코드를 올린 뒤 AWS 가 인증서를 ISSUED 로 바꿀 때까지 기다린다(보통 1~3분).
# ⚠️ 이게 없으면 인증서가 PENDING_VALIDATION 인 채로 ALB 리스너·CloudFront 가 붙으려다
#    UnsupportedCertificate 로 깨진다. 그래서 outputs 도 certificate.arn 이 아니라
#    certificate_validation.certificate_arn 을 내보낸다.
resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [aws_route53_record.acm_validation.fqdn]
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.virginia

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [aws_route53_record.acm_validation.fqdn]
}