# edge 모듈 - variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  description = "루트 도메인. 예: myminiinfra.store (끝에 점 없이)"
  type        = string
}

variable "alb_dns_name" {
  description = <<-EOT
    ALB Ingress 가 만든 로드밸런서 DNS 이름.
    예: k8s-hailcast-xxxx-1234567890.ap-northeast-2.elb.amazonaws.com

    비어 있으면(기본) CloudFront·레코드를 만들지 않고 ACM 인증서만 발급한다.
    → ALB 가 아직 없어도 apply 가 깨지지 않는다. #37 의 enable_app_irsa 와 같은 방식.
    배포팀이 Ingress 를 올린 뒤 `kubectl get ingress -n hailcast` 로 얻어 tfvars 에 넣는다.
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}