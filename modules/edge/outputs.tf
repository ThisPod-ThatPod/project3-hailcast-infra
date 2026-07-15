# edge 모듈 - outputs.tf

# ⭐ 배포팀 인터페이스 — Ingress annotation 에 넣을 값
#    alb.ingress.kubernetes.io/certificate-arn: <이 값>
output "alb_certificate_arn" {
  description = "ALB 용 ACM 인증서 ARN (서울). 배포팀이 Ingress annotation 에 사용"
  value       = aws_acm_certificate_validation.alb.certificate_arn
}

output "cloudfront_certificate_arn" {
  description = "CloudFront 용 ACM 인증서 ARN (us-east-1)"
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "cloudfront_domain_name" {
  description = "CloudFront 자동 주소 (d111111abcdef8.cloudfront.net)"
  value       = local.cloudfront_enabled ? aws_cloudfront_distribution.this[0].domain_name : ""
}

output "origin_domain_name" {
  description = "CloudFront 가 오리진으로 부르는 주소. 배포팀 Ingress host 규칙에 필요"
  value       = local.origin_domain
}

output "service_url" {
  description = "사용자가 접속할 주소"
  value       = local.cloudfront_enabled ? "https://${var.domain_name}" : ""
}