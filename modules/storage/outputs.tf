# storage 모듈 - outputs.tf (골격)
# 기존 ECR 관련 output 유지 

output "model_bucket_name" {
  description = "모델·예측 JSON 저장 버킷 이름 (predict·CI 참조)"
  value       = aws_s3_bucket.model_bucket.id
}

output "model_bucket_arn" {
  description = "모델 버킷 ARN (IRSA 정책 참조)"
  value       = aws_s3_bucket.model_bucket.arn
}