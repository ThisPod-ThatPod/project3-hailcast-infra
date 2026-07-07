# data 모듈 - main.tf
# Secrets: RDS(PostgreSQL) 마스터 자격증명을 Secrets Manager 로 관리한다.
#
# 원칙(INSTRUCTIONS): DB 비밀번호는 .tf 에 절대 하드코딩하지 않는다.
#   random_password 로 생성 → Secrets Manager 에만 저장 → RDS 가 나중에 이 시크릿을 참조.
# 지금은 RDS 가 아직 없어도 시크릿을 먼저 만들 수 있다(자립적). RDS 생성 시 ARN 만 연결.

locals {
  name_prefix = "${var.project_name}-${var.environment}" # hailcast-dev
}

# 1) 무작위 비밀번호 생성
#    RDS 마스터 비번은 '/', '@', '"', 공백을 못 쓰므로 특수문자 집합을 안전하게 제한한다.
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}"
}

# 2) 시크릿 '상자' 생성
#    recovery_window_in_days = 0 → 데모에서 terraform destroy 후 곧바로 같은 이름으로 재생성 가능.
#    (기본 30일이면 삭제 예약된 이름과 충돌해 재apply 가 실패한다. FinOps 데모 특성상 0으로 둔다.)
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}-rds-postgres-credentials"
  description             = "RDS(PostgreSQL) 마스터 자격증명 - hailcast ${var.environment}"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-postgres-credentials"
  })
}

# 3) 상자에 실제 값 저장 (username + password 를 JSON 한 덩어리로)
#    RDS/로테이션이 기대하는 표준 포맷이라 나중에 자동 로테이션도 붙이기 쉽다.
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}
