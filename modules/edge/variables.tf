# edge 모듈 - variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  description = "서비스 도메인. 예: hailcast.myminiinfra.store (끝에 점 없이). 이 이름의 호스팅 영역을 data 로 조회하므로 영역이 먼저 있어야 한다"
  type        = string
}

variable "alb_dns_name" {
  description = <<-EOT
    ALB Ingress 가 만든 로드밸런서 DNS 이름.
    예: k8s-hailcast-xxxx-1234567890.ap-northeast-2.elb.amazonaws.com

    비어 있으면 CloudFront·레코드를 만들지 않고 ACM 인증서만 발급한다.
    → ALB 가 아직 없어도 apply 가 깨지지 않는다. #37 의 enable_app_irsa 와 같은 방식.
    루트(envs/dev)는 이 값을 tfvars 가 아니라 변수 기본값에 둔다. CI 가 tfvars 없이 돌기 때문이다(규약서 §5-6).
    그래서 루트 기본 경로는 ALB 가 이미 있는 것을 전제한다.
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}