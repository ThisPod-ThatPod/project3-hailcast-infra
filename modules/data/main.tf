# data 모듈 - main.tf
# RDS 마스터 비번은 RDS 가 자동 생성해 Secrets Manager 에 넣는다(rds/main.tf 의 manage_master_user_password).
# 비번이 코드·tfstate 어디에도 평문으로 남지 않는다. ESO 가 그 시크릿을 읽어 K8s Secret 으로 동기화한다(§5-4).

locals {
  name_prefix = "${var.project_name}-${var.environment}" # hailcast-dev
}

# ── RDS 보안그룹 ──
# 규약서 §5-5: RDS SG 는 '5432 를 노드 SG 에서 온 것만' 허용한다.
# SG 자체는 zero-inbound 로 만들고, 5432 ingress 는 rds_ingress.tf(M4)에서
# 노드 SG(eks 모듈 출력)를 지목해 추가한다.
#
# ⚠️ 규칙은 인라인 블록이 아니라 '독립 rule 리소스'로만 관리한다.
#    인라인 블록과 독립 rule 리소스를 섞으면 Terraform 이 서로의 규칙을
#    매 apply 마다 지웠다 넣었다 하며 충돌한다(AWS provider 공식 경고).
#    → egress·ingress 모두 독립 리소스로 두어 관리 방식을 통일한다.
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg-rds"
  description = "RDS(PostgreSQL) - 5432 inbound from node SG only (ingress는 노드 SG 생성 후 추가)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-sg-rds"
  }
}

# RDS 는 아웃바운드를 먼저 개시하지 않지만, 관례상 전체 egress 허용(보안 초점은 zero-inbound).
resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id
  description       = "all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── RDS 인스턴스 (서브모듈) ──
# 비번은 RDS 가 자동 생성·관리한다(rds 서브모듈의 manage_master_user_password). 여기선 넘기지 않는다.
module "rds" {
  source = "./rds"

  project_name           = var.project_name
  environment            = var.environment
  db_name                = var.db_name
  db_username            = var.db_username
  instance_class         = var.instance_class
  engine_version         = var.engine_version
  allocated_storage      = var.allocated_storage
  subnet_ids             = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds.id]
  rds_availability_zone  = var.rds_availability_zone
}

# ── DB 주소를 Parameter Store 에 게시 (비밀 아님 → 무료 Parameter Store) ──
# 규약서 §5-4: /hailcast/dev/rds/endpoint. 앱이 이 경로로 접속 주소를 읽는다.
# 포트(5432)는 PostgreSQL 고정값이라 여기엔 '호스트명만' 저장한다(rds.address).
# → 앱은 host + 5432 로 조합해 접속. rds 서브모듈의 address output 설명과도 일치.
resource "aws_ssm_parameter" "rds_endpoint" {
  name        = "/${var.project_name}/${var.environment}/rds/endpoint"
  description = "RDS(PostgreSQL) 호스트명(포트 제외). 비밀 아님."
  type        = "String"
  value       = module.rds.address
}
