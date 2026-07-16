# edge 모듈 - cloudfront.tf

# ALB 는 배포팀 Ingress 가 만든다(Terraform 이 안 만든다). 그래서 주소를 변수로 받는다.
# 이 리전 ALB 들이 공통으로 쓰는 Route53 zone id — alias 레코드에 필요하다.
data "aws_lb_hosted_zone_id" "alb" {
  load_balancer_type = "application" # 수업 예제는 NLB("network") 였다. 우리는 ALB.
}

# ── origin.<도메인> → ALB ─────────────────────────
# ⚠️ 왜 ALB 의 AWS 자동 주소를 CloudFront 오리진으로 바로 안 쓰나:
#    CloudFront 가 오리진에 HTTPS 로 붙을 때, 오리진이 내미는 인증서의 도메인이
#    오리진 주소와 일치해야 한다. ALB 자동 주소(k8s-....elb.amazonaws.com)에
#    우리 인증서(*.myminiinfra.store)를 붙이면 이름이 안 맞아 502 가 난다.
#    → 우리 도메인으로 이름을 하나 파서 ALB 를 가리키고, CloudFront 는 그 이름으로 부른다.
resource "aws_route53_record" "origin" {
  count = local.cloudfront_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.origin_domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = data.aws_lb_hosted_zone_id.alb.id
    evaluate_target_health = false
  }
}

# ── 관리형 캐시 정책 (AWS 제공) ────────────────────
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# ⚠️ AllViewer 가 아니라 AllViewerExceptHostHeader 다. Host 하나 차이가 배포팀 계약을 가른다.
#   AllViewer 는 뷰어의 Host(myminiinfra.store · www.myminiinfra.store)를 그대로 오리진에 넘긴다.
#   그런데 기본 동작(아래 default_cache_behavior)은 origin request policy 가 없어서 CloudFront 가
#   Host 를 오리진 도메인(origin.myminiinfra.store)으로 바꿔 넣는다.
#   → 같은 배포판인데 ALB 가 보는 Host 가 경로마다 갈린다. 배포팀이 Ingress 에
#     host: origin.<도메인> 하나만 걸면 / 는 뜨고 /api/* 만 ALB 기본 404 로 떨어진다.
#     (TLS SNI 는 양쪽 다 origin.<도메인> 이라 인증서는 맞는다 → 502 가 아니라 404 다)
#
#   AllViewerExceptHostHeader = AllViewer − Host 다. 쿠키·쿼리스트링·나머지 헤더는 그대로 넘긴다.
#   Host 를 빼면 CloudFront 가 오리진 도메인으로 '새 Host' 를 넣어준다(AWS 문서).
#   → 두 동작 모두 Host = origin.<도메인> 으로 통일 → 배포팀 계약은 호스트 하나로 유지된다.
#   (2026-07-16 · 이미선 리뷰 지적)
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ── 배포판 ────────────────────────────────────────
resource "aws_cloudfront_distribution" "this" {
  count = local.cloudfront_enabled ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix} edge"
  aliases         = [var.domain_name, "www.${var.domain_name}"]

  # PriceClass_200 = 아시아 포함, 남미·아프리카 엣지 제외 → 불필요한 비용 제거(FinOps)
  price_class = "PriceClass_200"

  origin {
    domain_name = local.origin_domain
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 기본 = 프론트엔드(nginx 정적 파드) → 캐시한다
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id = data.aws_cloudfront_cache_policy.optimized.id
  }

  # /api/* = 콜 처리 API → 캐시하면 콜 상태가 굳는다. 반드시 캐시 끔.
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-cloudfront" })
}