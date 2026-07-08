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

# ── RDS 보안그룹 ──
# 규약서 §5-5: RDS SG 는 '5432 를 노드 SG 에서 온 것만' 허용해야 한다.
# 그러나 노드 SG 는 eks 클러스터/노드그룹과 함께 아직 생성 전이라 지금은 대상이 없다.
# → SG 는 zero-inbound(인바운드 규칙 0개)로 먼저 만들고, 5432 ingress 는
#   노드 SG 가 생기는 PR 에서 aws_vpc_security_group_ingress_rule 로 추가한다.
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg-rds"
  description = "RDS(PostgreSQL) - 5432 inbound from node SG only (ingress는 노드 SG 생성 후 추가)"
  vpc_id      = var.vpc_id

  # RDS 는 아웃바운드를 먼저 개시하지 않지만, 관례상 전체 egress 허용(보안 초점은 zero-inbound).
  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-rds"
  }
}

# ── RDS 인스턴스 (서브모듈) ──
# 비번은 root 로 output 하지 않고, 위에서 만든 random_password 를 여기서 '내부 전달'한다.
# → 시크릿(Secrets Manager)에 저장된 값과 실제 DB 비번이 항상 같은 소스로 일치한다.
module "rds" {
  source = "./rds"

  project_name           = var.project_name
  environment            = var.environment
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = random_password.db.result
  instance_class         = var.instance_class
  engine_version         = var.engine_version
  allocated_storage      = var.allocated_storage
  subnet_ids             = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds.id]
  rds_availability_zone  = var.rds_availability_zone
}

# ── DB 주소를 Parameter Store 에 게시 (비밀 아님 → 무료 Parameter Store) ──
# 규약서 §5-4: /hailcast/dev/rds/endpoint. 앱이 이 경로로 접속 주소를 읽는다.
resource "aws_ssm_parameter" "rds_endpoint" {
  name        = "/${var.project_name}/${var.environment}/rds/endpoint"
  description = "RDS(PostgreSQL) 접속 엔드포인트 (host:port). 비밀 아님."
  type        = "String"
  value       = module.rds.primary_endpoint
}
