# 1. 일반(Standard) Dead Letter Queue (DLQ) 생성
resource "aws_sqs_queue" "call_queue_dlq" {
  name                      = "hailcast-dev-call-queue-dlq"
  message_retention_seconds = 1209600 # 14일 보관

  tags = {
    Name        = "hailcast-dev-call-queue-dlq"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# 2. 메인 일반(Standard) SQS 콜 데이터 큐 생성
resource "aws_sqs_queue" "call_queue" {
  name                      = "hailcast-dev-call-queue"
  delay_seconds             = 0
  max_message_size          = 262144 # 256 KB
  message_retention_seconds = 345600 # 4일 보관
  receive_wait_time_seconds = 20     # Long Polling 활성화 (KEDA 지표 조회 및 워커 비용 최적화)

  # 3회 이상 메시지 처리 실패 시 DLQ로 전송
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.call_queue_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "hailcast-dev-call-queue"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}