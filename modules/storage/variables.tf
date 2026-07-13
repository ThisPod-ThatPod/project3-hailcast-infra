# storage 모듈 - variables.tf (골격)
variable "project" {
  description = "프로젝트 이름 (예: hailcast)"
  type        = string
}

variable "environment" {
  description = "실행 환경 (예: dev)"
  type        = string
}
