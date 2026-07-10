# cicd 모듈 - variables.tf
variable "project_name" {
  description = "프로젝트 접두사 (예: hailcast)."
  type        = string
  default     = "hailcast"
}

variable "environment" {
  description = "환경 구분자 (예: dev)."
  type        = string
  default     = "dev"
}

variable "create_oidc_provider" {
  description = "계정에 GitHub OIDC provider 가 아직 없으면 true(생성). 이미 있으면 false 로 두고 기존 것을 참조한다. provider 는 계정당 1개라 중복 생성 시 EntityAlreadyExists 로 apply 가 깨진다."
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub 조직/사용자명."
  type        = string
  default     = "ThisPod-ThatPod"
}

variable "github_repo" {
  description = "이 역할을 맡을(assume) GitHub 레포명. 신뢰정책 sub 를 이 레포로 좁힌다."
  type        = string
  default     = "project3-hailcast-app"
}

variable "tags" {
  description = "공통 태그."
  type        = map(string)
  default     = {}
}
