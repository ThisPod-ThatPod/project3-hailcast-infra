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
