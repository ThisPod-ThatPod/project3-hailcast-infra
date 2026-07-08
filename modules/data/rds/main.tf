
resource "aws_db_subnet_group" "db_sg" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_db_instance" "primary" {
  identifier        = "${var.project_name}-${var.environment}-rds-primary"
  allocated_storage = var.allocated_storage
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class

  availability_zone = var.rds_availability_zone
  multi_az          = var.rds_multi_az             

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.db_sg.name
  vpc_security_group_ids = var.vpc_security_group_ids

  publicly_accessible     = false
  skip_final_snapshot     = true
}
