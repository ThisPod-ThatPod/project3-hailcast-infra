# eks 모듈 - iam.tf
# 클러스터 생성보다 '먼저' 있어야 하는 두 역할. OIDC(IRSA)와 무관해 지금 만들 수 있다.

# ── 1) EKS 컨트롤플레인 역할 ──────────────────────────────────
#    EKS 서비스가 맡아 클러스터를 운영한다(ENI·로드밸런서 등 관리).
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = merge(var.tags, { Name = "${local.name_prefix}-eks-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── 2) 노드그룹 역할 ─────────────────────────────────────────
#    워커 노드(EC2)가 맡는다. 클러스터 합류(WorkerNodePolicy) · 파드 네트워킹(CNI) ·
#    ECR 이미지 pull(ReadOnly) · SSM 접속(키 없이 노드 진입, 운영 편의).
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = merge(var.tags, { Name = "${local.name_prefix}-eks-node-role" })
}

# 노드에 필요한 AWS 관리형 정책 4종 (표준 조합). ARN 은 상수라 for_each 에 안전하다.
locals {
  node_managed_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(local.node_managed_policies)
  role       = aws_iam_role.node.name
  policy_arn = each.value
}
