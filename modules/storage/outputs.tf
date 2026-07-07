# storage 모듈 - outputs.tf
# 이미지 push/pull 대상 URL. app 레포 CI(push 목적지)와 manifests(이미지 경로)가 참조한다.

# { predictor = "1234.dkr.ecr.ap-northeast-2.amazonaws.com/hailcast-dev-predictor", ... }
output "repository_urls" {
  description = "서비스 짧은 이름 → ECR repository URL 매핑."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "서비스 짧은 이름 → ECR repository ARN 매핑."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
