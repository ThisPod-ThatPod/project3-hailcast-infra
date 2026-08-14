# envs/dev - outputs.tf
# 다른 사람(또는 이후 배선될 클러스터 본체·앱)이 참조할 이 환경의 결과값만 골라 노출한다.
# 시크릿 '값'은 절대 output 하지 않는다 — ARN 만 넘긴다(민감정보 state 노출 방지).

# ── 네트워크 ──
output "vpc_id" {
  description = "생성된 VPC ID."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록(인터넷 향 LB·NAT)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록(EKS 노드·파드)."
  value       = module.network.private_subnet_ids
}

# ── 데이터 ──
output "rds_master_secret_arn" {
  description = "RDS 자동생성 마스터 비번 시크릿 ARN(IRSA eso 가 이 ARN 으로 참조)."
  value       = module.data.rds_master_secret_arn
}

output "rds_endpoint" {
  description = "RDS 접속 엔드포인트(host:port). 앱 DB 연결·KEDA 참조 계약값."
  value       = module.data.rds_endpoint
}

# ── SQS 콜 큐 ──
# 배포팀이 ConfigMap·ScaledObject 에 넣을 값이라 루트에서 꺼내 쓸 수 있게 노출한다.
#   terraform output -raw sqs_queue_url
output "sqs_queue_arn" {
  description = "콜 큐 ARN. eks 모듈 IRSA 정책이 Resource 로 지목(§7-1)."
  value       = module.data.sqs_queue_arn
}

output "sqs_queue_url" {
  description = "콜 큐 URL. 배포팀 ConfigMap(SQS_QUEUE_URL) · KEDA ScaledObject 의 queueURL."
  value       = module.data.sqs_queue_url
}

output "sqs_queue_name" {
  description = "콜 큐 이름(hailcast-dev-call-queue)."
  value       = module.data.sqs_queue_name
}

# ── SQS Karpenter 중단 큐 ──
output "karpenter_queue_arn" {
  description = "Karpenter 중단 큐 ARN. eks 모듈 IRSA karpenter 정책이 지목(§7-1)."
  value       = module.data.karpenter_queue_arn
}

output "karpenter_queue_name" {
  description = "Karpenter 중단 큐 이름(hailcast-dev). 배포팀 Helm: settings.interruptionQueue(§8)."
  value       = module.data.karpenter_queue_name
}

# ── EKS 선행 IAM (클러스터 생성 시 주입) ──
output "eks_cluster_iam_role_arn" {
  description = "EKS 컨트롤플레인 역할 ARN."
  value       = module.eks.cluster_iam_role_arn
}

output "eks_node_iam_role_arn" {
  description = "노드그룹 역할 ARN(관리형 노드그룹·Karpenter EC2NodeClass 에서 사용)."
  value       = module.eks.node_iam_role_arn
}

# ── EKS 클러스터 본체 (M1) — manifests·애드온·IRSA 계약(§7) ──
output "eks_cluster_name" {
  description = "EKS 클러스터 이름."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS 클러스터 API 엔드포인트."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "EKS 자동생성 클러스터 SG ID(노드 SG·RDS ingress 참조)."
  value       = module.eks.cluster_security_group_id
}

output "eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN(IRSA 전제)."
  value       = module.eks.oidc_provider_arn
}

output "eks_node_security_group_id" {
  description = "전용 노드 SG ID(M4 RDS 5432 ingress 가 이 SG 를 지목 · Karpenter EC2NodeClass 가 태그로 발견)."
  value       = module.eks.node_security_group_id
}

output "eks_node_group_name" {
  description = "system 관리형 노드그룹 이름(운영 조회·kubectl 대조용)."
  value       = module.eks.node_group_name
}

output "eks_alb_cloudfront_sg_id" {
  description = "ALB 인바운드를 CloudFront 로만 제한하는 SG ID. 배포팀 Ingress annotation 전달값."
  value       = module.eks.alb_cloudfront_sg_id
}

output "eks_irsa_role_arns" {
  description = "IRSA 역할 키→ARN 맵. manifests SA 애노테이션이 참조. 종수·목록은 규약서 §5-3 이 정한다."
  value       = module.eks.irsa_role_arns
}

# ── 스토리지 ──
output "ecr_repository_urls" {
  description = "ECR 레포 이름→URL 맵(app CI push 대상 · manifests 이미지 경로)."
  value       = module.storage.repository_urls
}

# ── CI/CD ──
output "github_actions_role_arn" {
  description = "app 레포 CI 가 assume 할 ECR push 역할 ARN(gha-ecr)."
  value       = module.cicd.github_actions_role_arn
}

output "gha_tf_plan_role_arn" {
  description = "terraform plan 전용(읽기) 역할 ARN. 워크플로 plan job 의 role-to-assume."
  value       = module.cicd.gha_tf_plan_role_arn
}

output "gha_tf_apply_role_arn" {
  description = "terraform apply 역할 ARN. GitHub environment 'infra-apply' 승인 후에만 assume 된다."
  value       = module.cicd.gha_tf_apply_role_arn
}

# ── S3 ──
output "model_bucket_arn" {
  description = "S3 모델 버킷 ARN (IRSA predict 가 소비)"
  value       = module.storage.model_bucket_arn
}
output "model_bucket_name" {
  description = "S3 모델 버킷 이름"
  value       = module.storage.model_bucket_name
}

# CUR 버킷 이름은 랜덤 접미사 때문에 apply 전에는 알 수 없다.
# 사람이 CLI 로 CUR 정의를 만들 때 이 값으로 버킷을 지목한다(명령은 규약서 §5-9).
output "cur_bucket_name" {
  description = "CUR 저장 버킷 이름. CUR 정의를 만들 때 지목할 버킷"
  value       = module.storage.cur_bucket_name
}

output "cur_bucket_arn" {
  description = "CUR 저장 버킷 ARN (Athena 와, 앞으로 만들 OpenCost IRSA 가 소비)"
  value       = module.storage.cur_bucket_arn
}

output "cur_prefix" {
  description = "CUR 정의에 입력할 S3 프리픽스"
  value       = module.storage.cur_prefix
}

output "athena_results_location" {
  description = "Athena 쿼리 결과를 둘 위치(s3:// URI). 이 값을 쓸 Workgroup 은 아직 없다"
  value       = module.storage.athena_results_location
}

output "alb_certificate_arn" {
  description = "배포팀이 Ingress annotation(alb.ingress.kubernetes.io/certificate-arn)에 넣을 값"
  value       = var.enable_edge ? module.edge[0].alb_certificate_arn : ""
}

output "service_url" {
  value = var.enable_edge ? module.edge[0].service_url : ""
}

output "origin_domain_name" {
  value = var.enable_edge ? module.edge[0].origin_domain_name : ""
}

# NS 위임이 부모 도메인 계정에 걸려 있어서, 위임 전에는 서비스 도메인이 해석되지 않는다.
# 그때 이 주소를 직접 때리면 DNS 없이 엣지를 검증할 수 있다. CloudFront 가 이 호스트에는
# 자기 기본 인증서를 내주고, origin request policy 가 Host 를 오리진 도메인으로 바꿔 보내므로
# ALB 라우팅까지 함께 확인된다.
output "cloudfront_domain_name" {
  description = "CloudFront 자동 주소. DNS 위임 전 엣지 검증용"
  value       = var.enable_edge ? module.edge[0].cloudfront_domain_name : ""
}