# network 모듈 - endpoints.tf
# Gateway 엔드포인트: S3·DynamoDB 로 가는 트래픽을 NAT/인터넷이 아니라 AWS 내부망으로 보낸다.
#   효과: (1) Gateway 타입은 '무료' (2) NAT 데이터 전송요금 절감 (3) 트래픽이 VPC 밖으로 안 나감(보안).
#   연결 방식: 라우팅 테이블에 해당 서비스용 prefix-list 경로를 자동 주입 → private RT 하나에만 붙이면 됨.

# 리전은 provider 설정으로 이미 확정된 값이라 변수로 받지 않고 data 소스로 파생한다(cicd 모듈과 동일 패턴).
data "aws_region" "current" {}

# ── S3 게이트웨이 엔드포인트 (모델 아티팩트·예측 JSON 저장소) ──
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${local.name_prefix}-vpce-s3"
  }
}

# ── DynamoDB 게이트웨이 엔드포인트 (예측 오답노트 등) ──
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${local.name_prefix}-vpce-dynamodb"
  }
}
