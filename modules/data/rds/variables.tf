variable "project_name" {
  description = "리소스 이름에 공통으로 붙는 이름"
  type        = string
}

variable "environment" {
  description = "배포 환경"
  type        = string
}

variable "db_name" {
  description = "RDS 데이터베이스 이름"
  type        = string
}

variable "db_username" {
  description = "RDS 사용자 이름"
  type        = string
}

variable "db_password" {
  description = "RDS 비밀번호"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS 인스턴스 타입"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL 버전"
  type        = string
}

variable "allocated_storage" {
  description = "RDS 스토리지 크기 (GB 단위)"
  type        = number
}

variable "vpc_security_group_ids" {
  description = "RDS에 적용할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "subnet_ids" {
  description = "DB 서브넷 그룹에 포함할 서브넷 ID 목록 (프라이빗)"
  type        = list(string)
}

variable "rds_availability_zone" {
  description = "RDS 인스턴스를 고정할 가용 영역 (Private Subnet A 위치)"
  type        = string
}