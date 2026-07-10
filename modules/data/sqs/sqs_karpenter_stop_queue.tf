resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name                      = "hailcast-dev-eks"
  message_retention_seconds = 300 # Spot 중단 처리용
  sqs_managed_sse_enabled   = true

  tags = {
    Name        = "hailcast-dev-eks"
    Environment = "dev"
    Component   = "Karpenter-Interruption"
  }
}