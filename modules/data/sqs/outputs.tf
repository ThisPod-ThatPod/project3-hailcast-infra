output "sqs_queue_url" {
  description = "SQS 콜 데이터 큐의 URL (애플리케이션 컨테이너 및 KEDA Scaler 환경 변수 주입용)"
  value       = aws_sqs_queue.call_queue.id
}

output "sqs_queue_arn" {
  description = "SQS 콜 데이터 큐의 ARN (별도의 IAM 모듈이나 타 인프라 파일에서 참조할 때 사용)"
  value       = aws_sqs_queue.call_queue.arn
}

output "call_queue_name" {
  description = "SQS 콜 데이터 큐의 이름"
  value       = aws_sqs_queue.call_queue.name
}