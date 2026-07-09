# eks 모듈 - variables.tf
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

variable "tags" {
  description = "공통 태그 (비용 배분·OpenCost 판별용)."
  type        = map(string)
  default     = {}
}

# ── 클러스터 배선용 입력 (envs/dev 가 network 출력을 스레딩) ──

variable "private_subnet_ids" {
  description = "컨트롤플레인 ENI·노드가 들어갈 프라이빗 서브넷 ID 목록(≥2 AZ). network 출력."
  type        = list(string)
}

variable "cluster_version" {
  description = "EKS 버전. ⚠️ apply 전 AWS 표준지원 버전 재확인(규약서 §5-3)."
  type        = string
  default     = "1.35"
}

variable "public_access_cidrs" {
  description = "퍼블릭 엔드포인트 허용 대역. 데모 기본 0.0.0.0/0(=네트워크 도달만 허용, 조작은 IAM+RBAC 필요). 운영 시 내 IP/CIDR 로 조인다."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── 노드그룹(M2) 입력 ──

variable "vpc_id" {
  description = "노드 SG 를 붙일 VPC ID (network 출력)."
  type        = string
}

variable "node_instance_types" {
  description = "system 노드그룹 인스턴스 타입. 플랫폼(ArgoCD·Prometheus) 수용 위해 t3.large."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_min_size" {
  description = "system 노드그룹 최소 노드 수(HA 위해 2)."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "system 노드그룹 희망 노드 수."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "system 노드그룹 최대 노드 수(롤링·일시 여유 상한)."
  type        = number
  default     = 3
}
