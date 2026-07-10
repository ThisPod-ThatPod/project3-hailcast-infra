# data 모듈 - outputs.tf
# 시크릿 '값'은 절대 output 하지 않는다. ARN·이름만 넘겨 RDS/IRSA 가 참조하게 한다.

output "db_credentials_secret_arn" {
  description = "RDS 자격증명 시크릿 ARN (RDS 연결 또는 IRSA 최소권한 정책이 이 ARN 만 허용)."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_credentials_secret_name" {
  description = "RDS 자격증명 시크릿 이름."
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "rds_endpoint" {
  description = "RDS 접속 엔드포인트 (host:port). 앱·KEDA 가 참조하는 계약값(§7)."
  value       = module.rds.primary_endpoint
}

output "rds_security_group_id" {
  description = "RDS SG ID. 노드 SG 생성 PR 에서 5432 ingress 규칙이 이 SG 를 대상으로 붙는다."
  value       = aws_security_group.rds.id
}
