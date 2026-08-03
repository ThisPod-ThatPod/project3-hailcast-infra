# data 모듈 - variables.tf
# 이름 파생과 자격증명 구성에 쓰는 입력값. 실제 값은 envs/dev 에서 주입한다.

variable "project_name" {
  description = "프로젝트 접두사. 모든 리소스 이름의 앞부분 (예: hailcast)."
  type        = string
  default     = "hailcast"
}

variable "environment" {
  description = "환경 구분자. 이름 중간에 들어간다 (예: dev)."
  type        = string
  default     = "dev"
}

variable "db_username" {
  description = "RDS 마스터 사용자명. 비밀번호는 코드에 두지 않고 Secrets Manager 가 무작위 생성한다."
  type        = string
  default     = "hailcast_admin"
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그 (비용 배분·OpenCost 판별용)."
  type        = map(string)
  default     = {}
}

# ── RDS 배선용 입력 (envs/dev 가 network 출력을 스레딩) ──

variable "vpc_id" {
  description = "RDS SG 를 붙일 VPC ID (network 모듈 출력)."
  type        = string
}

variable "private_subnet_ids" {
  description = "DB 서브넷 그룹에 넣을 프라이빗 서브넷 ID 목록 (network 모듈 출력, 2개 AZ)."
  type        = list(string)
}

variable "rds_availability_zone" {
  description = "RDS 인스턴스를 고정할 단일 AZ (예: ap-northeast-2a). Single-AZ 데모."
  type        = string
}

variable "node_security_group_id" {
  description = "EKS 노드 SG ID (eks 모듈 출력). RDS 5432 인바운드를 이 SG 에서 온 트래픽만 허용한다(§5-5)."
  type        = string
}

variable "db_name" {
  description = "생성할 초기 데이터베이스 이름."
  type        = string
  default     = "hailcast"
}

variable "engine_version" {
  description = "PostgreSQL 메이저 버전. 메이저만 지정하면 RDS 가 최신 마이너를 선택한다."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS 인스턴스 타입 (데모: db.t3.micro)."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "RDS 스토리지 크기(GB)."
  type        = number
  default     = 20
}
