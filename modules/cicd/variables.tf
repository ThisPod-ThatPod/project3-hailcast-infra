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

# ── terraform 용 역할 2종 (§5-6) ──
variable "infra_repo" {
  description = "terraform 을 돌리는 GitHub 레포명. gha-tf-plan·gha-tf-apply 의 신뢰정책 sub 를 이 레포로 좁힌다."
  type        = string
  default     = "project3-hailcast-infra"
}

variable "tfstate_bucket" {
  description = <<-EOT
    tfstate S3 버킷 이름. plan 역할이 잠금 파일(.tflock)을 쓰고 지울 수 있어야 한다
    (use_lockfile=true). ReadOnlyAccess 는 PutObject 를 안 줘서 이 권한을 따로 붙인다.
    ⚠️ backend.tf 의 bucket 과 같은 값이어야 한다.
  EOT
  type        = string
}

variable "tfstate_key" {
  description = <<-EOT
    tfstate 오브젝트 키. plan 역할의 쓰기 권한을 '<이 키>.tflock' 하나로 좁히는 데 쓴다
    (버킷 전체에 쓰기를 주면 plan 역할이 state 자체를 덮어쓸 수 있다).
    ⚠️ backend.tf 의 key 와 같은 값이어야 한다. 어긋나면 plan 이 잠금을 못 걸어 죽는다.
  EOT
  type        = string
  default     = "dev/terraform.tfstate"
}

variable "apply_environment" {
  description = <<-EOT
    apply 역할을 맡을 수 있는 GitHub environment 이름.
    신뢰정책 sub 가 'repo:<org>/<repo>:environment:<이 값>' 으로 못 박히므로,
    이 environment 에 '필수 리뷰어'를 걸면 승인 전에는 토큰의 sub 가 달라져
    AWS 가 assume 자체를 거부한다 → 수동 승인 게이트가 AWS 레벨에서 강제된다.

    ⚠️ GitHub 레포 Settings → Environments 에 이 이름으로 환경을 만들어야 한다.
       없으면 apply job 이 돌지 않는다.
  EOT
  type        = string
  default     = "infra-apply"
}
