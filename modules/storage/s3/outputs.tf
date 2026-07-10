output "model_bucket_arn" {
  description = "모델 아티팩트 및 예측 결과가 저장되는 S3 버킷의 ARN (IRSA/IAM Policy 권한 설정 시 참조)"
  value       = aws_s3_bucket.model_bucket.arn
}

output "model_bucket_name" {
  description = "랜덤 접미사가 조합되어 전역에서 유일하게 생성된 S3 버킷의 실제 이름 (애플리케이션 환경 변수 등에서 참조)"
  value       = aws_s3_bucket.model_bucket.id
}