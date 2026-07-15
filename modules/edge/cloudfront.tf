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

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
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
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
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