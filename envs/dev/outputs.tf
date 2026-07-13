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
output "db_credentials_secret_arn" {
  description = "RDS 자격증명 시크릿 ARN(RDS·IRSA 가 이 ARN 으로 참조)."
  value       = module.data.db_credentials_secret_arn
}

output "rds_endpoint" {
  description = "RDS 접속 엔드포인트(host:port). 앱 DB 연결·KEDA 참조 계약값."
  value       = module.data.rds_endpoint
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

output "eks_irsa_role_arns" {
  description = "IRSA 역할 키→ARN 맵(§5-3). manifests SA 애노테이션이 참조. 현재 lbctrl·monitoring 2종, ARN 접점 해소 시 확장."
  value       = module.eks.irsa_role_arns
}

# ── 스토리지 ──
output "ecr_repository_urls" {
  description = "ECR 레포 이름→URL 맵(app CI push 대상 · manifests 이미지 경로)."
  value       = module.storage.repository_urls
}

# ── CI/CD ──
output "github_actions_role_arn" {
  description = "GitHub Actions 워크플로가 assume 할 역할 ARN."
  value       = module.cicd.github_actions_role_arn
}

# ── S3 ──
output "model_bucket_name" {
  description = "모델·예측 JSON 저장 버킷 이름 (predict·CI 참조)"
  value       = aws_s3_bucket.model_bucket.id
}

output "model_bucket_arn" {
  description = "모델 버킷 ARN (IRSA 정책 참조)"
  value       = aws_s3_bucket.model_bucket.arn
}