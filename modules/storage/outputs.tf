# storage 모듈 - outputs.tf
# 이미지 push/pull 대상 URL. app 레포 CI(push 목적지)와 manifests(이미지 경로)가 참조한다.

# { predict = "1234.dkr.ecr.ap-northeast-2.amazonaws.com/hailcast-dev-predict", ... }
output "repository_urls" {
  description = "서비스 짧은 이름 → ECR repository URL 매핑."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "서비스 짧은 이름 → ECR repository ARN 매핑."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "model_bucket_name" {
  description = "모델·예측 JSON 저장 버킷 이름 (predict·CI 참조)"
  value       = aws_s3_bucket.model_bucket.id
}

output "model_bucket_arn" {
  description = "모델 버킷 ARN (IRSA 정책 참조)"
  value       = aws_s3_bucket.model_bucket.arn
}

output "cur_bucket_name" {
  description = "CUR 저장 버킷 이름. CUR 정의를 만들 때 이 버킷을 지목한다."
  value       = aws_s3_bucket.cur.id
}

output "cur_bucket_arn" {
  description = "CUR 저장 버킷 ARN. Athena 와, 앞으로 만들 OpenCost IRSA 가 참조한다."
  value       = aws_s3_bucket.cur.arn
}

output "cur_prefix" {
  description = "CUR 정의에 입력할 S3 프리픽스."
  value       = var.cur_prefix
}

output "athena_results_prefix" {
  description = "Athena 쿼리 결과 프리픽스. eks 모듈의 opencost IRSA 정책이 이 값으로 경로를 좁힌다."
  value       = var.athena_results_prefix
}

output "athena_results_location" {
  description = "Athena 쿼리 결과를 둘 위치(s3:// URI). athena_workgroup_name 의 result_configuration 이 이 값을 그대로 쓴다."
  value       = "s3://${aws_s3_bucket.cur.id}/${var.athena_results_prefix}/"
}

output "glue_database_name" {
  description = "CUR Glue 데이터베이스 이름. OpenCost 설정과 Athena 쿼리가 참조한다."
  value       = aws_glue_catalog_database.cur.name
}

output "glue_database_arn" {
  description = "CUR Glue 데이터베이스 ARN. OpenCost IRSA 정책이 참조한다."
  value       = aws_glue_catalog_database.cur.arn
}

output "athena_workgroup_name" {
  description = "OpenCost 가 쓸 Athena workgroup 이름."
  value       = aws_athena_workgroup.opencost.name
}

output "athena_workgroup_arn" {
  description = "Athena workgroup ARN. OpenCost IRSA 정책이 참조한다."
  value       = aws_athena_workgroup.opencost.arn
}
