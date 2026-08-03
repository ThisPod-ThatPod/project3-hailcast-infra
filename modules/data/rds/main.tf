
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

resource "aws_db_instance" "primary" {
  # 규약서 §5-4 계약: hailcast-dev-rds-postgres
  identifier        = "${var.project_name}-${var.environment}-rds-postgres"
  allocated_storage = var.allocated_storage
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class

  # 데모는 단일 AZ 고정. Multi-AZ는 availability_zone(AZ 고정)과 논리 충돌하므로 false 하드코딩한다.
  # (변수로 두면 true 주입 시 apply 실패하는 '함정 변수'가 됨 → YAGNI·KISS)
  availability_zone = var.rds_availability_zone
  multi_az          = false

  db_name  = var.db_name
  username = var.db_username

  # 비번은 RDS 가 자동 생성해 Secrets Manager 에 넣는다. tfstate·코드에 평문이 안 남는다(§5-4).
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = var.vpc_security_group_ids

  # 콜 기록·날씨가 저장되는 DB → 저장 암호화 필수. t3.micro도 지원, 사실상 무비용.
  storage_encrypted = true

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-postgres"
  }
}
