# edge 모듈 - route53.tf
# 사용자가 치는 주소 → CloudFront

resource "aws_route53_record" "apex" {
  count = local.cloudfront_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  # alias = AWS 리소스를 가리키는 Route53 전용 레코드. 조회 요금이 없고 IP 가 바뀌어도 따라간다.
  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  count = local.cloudfront_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}