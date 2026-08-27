# envs/dev - variables.tf
# 이 파일은 '재사용 모듈'이 아니라 특정 환경(dev)의 루트다.
# 따라서 dev 고정값을 default 로 박아둔다 → tfvars 없이도 plan 이 돈다.
# (다른 값으로 돌리고 싶으면 -var 나 terraform.tfvars 로 덮으면 됨. tfvars 는 .gitignore 처리.)

variable "project_name" {
  description = "프로젝트 접두사. 모든 리소스 이름의 앞부분."
  type        = string
  default     = "hailcast"
}

variable "environment" {
  description = "환경 구분자."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "배포 리전. 서울(ap-northeast-2)."
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "VPC 전체 주소 대역(/16)."
  type        = string
  default     = "10.0.0.0/16"
}

# AZ 와 서브넷 CIDR 목록은 '같은 길이·같은 순서'여야 한다.
# network 모듈이 count.index 로 AZ[i] ↔ 서브넷[i] 를 1:1 매칭하기 때문.
variable "availability_zones" {
  description = "사용할 가용 영역(2개, HA). 서브넷 목록과 순서·개수를 맞춘다."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR(대문 쪽: LB·NAT)."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR(집 안쪽: EKS 노드·파드)."
  type        = list(string)
  default     = ["10.0.32.0/20", "10.0.48.0/20"]
}

# ── 클러스터 출입 명단 (eks 모듈 access.tf 로 넘어간다) ──────────────────
# 실제 ARN 은 terraform.tfvars(gitignore)에만. 이 레포는 퍼블릭이다.
variable "cluster_admin_principal_arns" {
  description = "클러스터 전권을 줄 IAM principal ARN 목록. apply 주체는 넣지 마라(자동 등재 → 중복 시 apply 실패)."
  type        = list(string)
  default     = []
}

variable "cluster_editor_principal_arns" {
  description = "앱 네임스페이스 안에서만 편집 권한을 줄 IAM principal ARN 목록."
  type        = list(string)
  default     = []
}

variable "enable_night_shutdown" {
  description = <<-EOT
    야간 절전(§5-8) 스위치. 매일 KST 02~10시에 시스템 노드그룹·RDS 를 내렸다 올린다.
    기본 false — 상시 가동 비용을 실측해 FinOps 자료로 쓰려고 꺼둔다.
  EOT
  type        = bool
  default     = false
}

variable "enable_edge" {
  description = <<-EOT
    엣지(Route53·CloudFront·ACM) 생성 스위치.
    2026-07-21 기본 true 로 승격 — NS 위임 생존 확인 후 1단계(인증서) apply 완료.
    CI 가 tfvars 없이 돌므로, 실물과 일치해야 하는 비밀 아닌 값은 tfvars 가 아니라 여기 기본값에 둔다.
    켜도 alb_dns_name 이 비면 인증서만 만든다.
  EOT
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "서비스 도메인. 이 이름의 Route53 호스팅 영역이 이미 있어야 한다(edge 모듈이 data 로 조회한다). 비밀 아님(공개 DNS) → CI 정합 위해 기본값에 실값을 둔다."
  type        = string
  default     = "hailcast.myminiinfra.store"
}

variable "alb_dns_name" {
  description = <<-EOT
    배포팀 Ingress 가 만든 ALB DNS. 비면 CloudFront 를 만들지 않는다.
    비밀 아님(공개 DNS) → CI 정합 위해 기본값에 실값을 둔다.
  EOT
  type        = string
  default     = "k8s-hailcastdev-6ad81285b1-209652505.ap-northeast-2.elb.amazonaws.com"
}