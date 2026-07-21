# schedule 모듈 - variables.tf

variable "project_name" {
  description = "프로젝트 이름(hailcast). 리소스 이름 접두어."
  type        = string
}

variable "environment" {
  description = "환경 이름(dev)."
  type        = string
}

variable "aws_region" {
  description = "리전. 노드그룹·RDS ARN 조립에 쓴다."
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (eks output). 노드그룹 지목에 쓴다."
  type        = string
}

variable "node_group_name" {
  description = "시스템 노드그룹 이름 (eks output). 야간에 0으로 내리는 대상."
  type        = string
}

# 시간 조정은 여기 cron 만 바꾼다(§5-8 · 타임존은 main.tf 에서 Asia/Seoul 고정).
# RDS 를 노드보다 먼저 올리는 이유: 기동에 수 분 걸려서, 앱이 뜰 때 DB 가 없는 구간을 없앤다.
variable "stop_nodes_cron" {
  description = "노드그룹 0 스케줄. 기본 매일 02:00 KST."
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "stop_rds_cron" {
  description = "RDS 정지 스케줄. 기본 매일 02:05 KST."
  type        = string
  default     = "cron(5 2 * * ? *)"
}

variable "start_rds_cron" {
  description = "RDS 시작 스케줄. 기본 매일 09:50 KST."
  type        = string
  default     = "cron(50 9 * * ? *)"
}

variable "start_nodes_cron" {
  description = "노드그룹 복원 스케줄. 기본 매일 10:00 KST."
  type        = string
  default     = "cron(0 10 * * ? *)"
}

variable "node_restore_min" {
  description = "아침 복원 시 노드그룹 min. eks 모듈 기본(2)과 맞춘다."
  type        = number
  default     = 2
}

variable "node_restore_desired" {
  description = "아침 복원 시 노드그룹 desired. eks 모듈 기본(2)과 맞춘다."
  type        = number
  default     = 2
}

variable "node_max" {
  description = "노드그룹 max. scalingConfig 가 세 값을 다 요구해서 함께 보낸다. eks 모듈 기본(3)과 맞춘다."
  type        = number
  default     = 3
}
