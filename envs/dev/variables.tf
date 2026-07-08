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
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR(집 안쪽: EKS 노드·파드)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}
