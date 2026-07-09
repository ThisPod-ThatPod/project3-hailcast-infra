# eks 모듈 - outputs.tf
output "cluster_iam_role_arn" {
  description = "EKS 컨트롤플레인 역할 ARN (클러스터 생성 시 사용)."
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "노드그룹 역할 ARN (관리형 노드그룹·Karpenter EC2NodeClass 에서 사용)."
  value       = aws_iam_role.node.arn
}

# ── 클러스터 본체 (M1) — 애드온·IRSA·manifests 가 소비하는 계약(§7) ──
output "cluster_name" {
  description = "EKS 클러스터 이름. 애드온·IRSA·kubeconfig 참조."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "클러스터 API 엔드포인트(kubeconfig server)."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "클러스터 CA 인증서(base64). kubeconfig 구성용."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS 가 자동 생성한 클러스터 보안그룹 ID. 노드 SG(M2)·RDS ingress(M4) 참조."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN. IRSA 신뢰정책의 Federated principal(§5-3)."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer_url" {
  description = "클러스터 OIDC issuer URL. IRSA 조건(sub/aud)에서 참조."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
