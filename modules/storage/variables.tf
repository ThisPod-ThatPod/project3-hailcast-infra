# storage 모듈 - variables.tf
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

# 만들 ECR 레포의 '서비스 짧은 이름' 목록.
# 최종 레포명은 <project>-<env>-<name> → cicd 역할의 push 대상(hailcast-dev-*)과 자동으로 맞물린다.
# 정적 리스트라 for_each 에 안전하다(apply 시점에 이미 값이 확정됨).
variable "repositories" {
  description = "ECR 레포로 만들 서비스 짧은 이름 목록. 실제 앱 서비스에 맞게 조정한다."
  type        = list(string)
  default     = ["predictor"]
}

# 보관할 태그 이미지 개수. 초과분은 오래된 것부터 자동 만료(비용 통제).
variable "image_keep_count" {
  description = "레포당 보관할 최신 태그 이미지 개수(초과분 자동 삭제)."
  type        = number
  default     = 10
}

variable "tags" {
  description = "공통 태그 (비용 배분·OpenCost 판별용)."
  type        = map(string)
  default     = {}
}
