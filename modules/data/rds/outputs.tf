output "primary_endpoint" {
  description = "RDS 접속 엔드포인트 (host:port). 앱 DB 연결·배선용."
  value       = aws_db_instance.primary.endpoint
}

output "address" {
  description = "RDS 호스트명(포트 제외). Parameter Store /hailcast/dev/rds/endpoint 저장용."
  value       = aws_db_instance.primary.address
}

output "port" {
  description = "RDS 포트 (PostgreSQL 기본 5432)."
  value       = aws_db_instance.primary.port
}

output "arn" {
  description = "RDS 인스턴스 ARN. IAM 정책·모니터링 참조용."
  value       = aws_db_instance.primary.arn
}
