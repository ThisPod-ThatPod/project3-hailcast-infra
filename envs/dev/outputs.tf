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

# ── EKS 선행 IAM (클러스터 생성 시 주입) ──
output "eks_cluster_iam_role_arn" {
  description = "EKS 컨트롤플레인 역할 ARN."
  value       = module.eks.cluster_iam_role_arn
}

output "eks_node_iam_role_arn" {
  description = "노드그룹 역할 ARN(관리형 노드그룹·Karpenter EC2NodeClass 에서 사용)."
  value       = module.eks.node_iam_role_arn
}

# ── CI/CD ──
output "github_actions_role_arn" {
  description = "GitHub Actions 워크플로가 assume 할 역할 ARN."
  value       = module.cicd.github_actions_role_arn
}
