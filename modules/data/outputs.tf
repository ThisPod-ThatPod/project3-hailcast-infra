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

# ── SQS 콜 큐 (§7 모듈 output 계약) ────────────────────────
# 이름이 곧 계약이다. eks(IRSA)·앱·KEDA 가 이 이름으로 값을 꺼내 쓴다.

output "sqs_queue_arn" {
  description = "콜 큐 ARN. eks 모듈의 IRSA 정책(call-api·worker·keda·predict)이 Resource 로 지목한다(§7-1)."
  value       = aws_sqs_queue.call.arn
}

output "sqs_queue_url" {
  description = <<-EOT
    콜 큐 URL. 배포팀이 ConfigMap 으로 앱에 주입하면(SQS_QUEUE_URL) 앱 어댑터가
    get_queue_url API 호출을 건너뛴다 → IRSA 세 역할에서 sqs:GetQueueUrl 을 뺄 수 있다(§5-3).
    KEDA ScaledObject 의 queueURL 도 이 값이다.
  EOT
  value       = aws_sqs_queue.call.url
}

output "sqs_queue_name" {
  description = "콜 큐 이름(hailcast-dev-call-queue). 앱이 큐 이름만 받는 경우의 참조값."
  value       = aws_sqs_queue.call.name
}
