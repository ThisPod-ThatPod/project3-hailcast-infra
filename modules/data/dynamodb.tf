# DynamoDB 오답노트 (규약서 §5-4). predict 가 예측 실패를 기록한다(IRSA predict 쓰기 전용).
# 온디맨드라 요청당 과금 — 데모에서 방치해도 사실상 무비용.
# 파티션키 prediction_date (date 는 DynamoDB 예약어라 회피), 정렬키 target_time (ISO).
# 예측값·실제값·차이는 스키마리스 속성이라 여기 선언하지 않는다.
resource "aws_dynamodb_table" "prediction_log" {
  name         = "${local.name_prefix}-prediction-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "prediction_date"
  range_key    = "target_time"

  attribute {
    name = "prediction_date"
    type = "S"
  }

  attribute {
    name = "target_time"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-prediction-log"
  })
}
