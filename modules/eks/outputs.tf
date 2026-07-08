# eks 모듈 - outputs.tf
output "cluster_iam_role_arn" {
  description = "EKS 컨트롤플레인 역할 ARN (클러스터 생성 시 사용)."
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "노드그룹 역할 ARN (관리형 노드그룹·Karpenter EC2NodeClass 에서 사용)."
  value       = aws_iam_role.node.arn
}
