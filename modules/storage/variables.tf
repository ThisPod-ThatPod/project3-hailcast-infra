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
  description = "ECR 레포로 만들 서비스 짧은 이름 목록. app 레포의 Dockerfile·manifests apps/ 와 1:1 로 맞춘다."
  type        = list(string)
  # simulator: 시연 부하를 만드는 유일한 발원지(app 레포 simulator/Dockerfile) — 없으면 큐가 비어 스케일링 시연 불가.
  # frontend : 화면 파일을 담은 nginx 정적 파드 이미지(S3 정적 호스팅 아님).
  default = ["call-api", "predict", "weather-cron", "worker", "simulator", "frontend"]
}

# 보관할 태그 이미지 개수. 초과분은 오래된 것부터 자동 만료(비용 통제).
# GitOps 밖에서 도는 파드(weather-cron·simulator·frontend)는 옛 태그에 고정돼 있어,
# 자기 소스가 안 바뀌어도 backend/common 변경분에 밀려 그 태그가 만료된다.
# 매니페스트 편입 전까지의 안전판으로 여유를 둔다.
variable "image_keep_count" {
  description = "레포당 보관할 최신 태그 이미지 개수(초과분 자동 삭제)."
  type        = number
  default     = 30
}

variable "tags" {
  description = "공통 태그 (비용 배분·OpenCost 판별용)."
  type        = map(string)
  default     = {}
}

