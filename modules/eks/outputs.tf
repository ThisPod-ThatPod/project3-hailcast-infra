# eks 모듈 - outputs.tf
output "cluster_iam_role_arn" {
  description = "EKS 컨트롤플레인 역할 ARN (클러스터 생성 시 사용)."
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "노드그룹 역할 ARN (관리형 노드그룹·Karpenter EC2NodeClass 에서 사용)."
  value       = aws_iam_role.node.arn
}

# ── 클러스터 본체 (M1) · 애드온·IRSA·manifests 가 소비하는 계약(§7) ──
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

# ── 노드그룹 (M2) ──
output "node_security_group_id" {
  description = "전용 노드 SG ID. M4 에서 RDS 5432 ingress 가 이 SG 를 지목한다(§5-5)."
  value       = aws_security_group.node.id
}

output "node_group_name" {
  description = "system 관리형 노드그룹 이름."
  value       = aws_eks_node_group.system.node_group_name
}

# ── IRSA (M3) · manifests 의 serviceaccount.yaml 이 eks.amazonaws.com/role-arn 으로 참조하는 계약(§7) ──
# 역할 키(lbctrl·monitoring·predict…) → 역할 ARN 맵.
#   enable_app_irsa = false → 2종(lbctrl·monitoring)
#   enable_app_irsa = true  → 10종 (규약서 §5-3 전체. base 2 + app 8)
# manifests 는 이 맵에서 자기 키를 뽑아 SA 애노테이션에 박는다. 키 이름이 흔들리면 '권한 없음'으로 이어진다(§8).
output "irsa_role_arns" {
  description = "IRSA 역할 키 → 역할 ARN 맵. manifests SA 애노테이션(eks.amazonaws.com/role-arn)이 소비."
  value       = { for key, role in aws_iam_role.irsa : key => role.arn }
}
