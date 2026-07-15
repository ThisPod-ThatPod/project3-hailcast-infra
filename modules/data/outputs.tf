# data 모듈 - outputs.tf
# 시크릿 '값'은 절대 output 하지 않는다. ARN·이름만 넘겨 RDS/IRSA 가 참조하게 한다.

output "rds_master_secret_arn" {
  description = "RDS 자동생성 마스터 비번 시크릿 ARN. eks IRSA eso 가 GetSecretValue 대상으로 지목(§7)."
  value       = module.rds.master_secret_arn
}

output "prediction_log_table_arn" {
  description = "DynamoDB 오답노트 테이블 ARN. eks IRSA predict 가 쓰기 대상으로 지목(§7)."
  value       = aws_dynamodb_table.prediction_log.arn
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

# ── SQS Karpenter 중단 큐 (§7 모듈 output 계약) ────────────

output "karpenter_queue_arn" {
  description = "Karpenter 중단 큐 ARN. eks 모듈의 IRSA karpenter 정책이 Resource 로 지목한다(§7-1)."
  value       = aws_sqs_queue.karpenter.arn
}

output "karpenter_queue_name" {
  description = <<-EOT
    Karpenter 중단 큐 이름(hailcast-dev). 배포팀이 Helm values 의
    settings.interruptionQueue 에 '반드시' 넘겨야 하는 값이다(§8 계약).
    안 넘기면 기본값이 빈 문자열이라 중단 처리 컨트롤러가 아예 등록되지 않는다.
  EOT
  value       = aws_sqs_queue.karpenter.name
}
