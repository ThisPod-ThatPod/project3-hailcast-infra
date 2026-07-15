# eks 모듈 - access.tf
# 클러스터 '출입 명단' — 사람이 kubectl 을 쓰려면 IAM principal 이 여기 올라야 한다.
#
# ⚠️ IRSA 와 방향이 반대다. 섞지 마라.
#     IAM → 클러스터 (사람이 들어온다) = access entry   ← 이 파일
#     클러스터 → AWS (파드가 나간다)   = IRSA           ← irsa.tf
#
# AWS 권한(IAM)과 클러스터 안 권한(K8s)은 별개 체계다.
# AdministratorAccess 를 갖고 있어도 클러스터 접근이 자동으로 주어지지 않는다.
#
# ⚠️ apply 를 실행한 principal 은 이 목록에 넣지 마라.
#    bootstrap_cluster_creator_admin_permissions = true(cluster.tf) 라서 클러스터를 만든
#    principal 은 EKS 가 자동으로 등재한다. 같은 principal 이 두 access entry 에 들어가면
#    "An IAM principal can't be included in more than one access entry" 로 apply 가 실패한다.
#
# for_each 의 키는 tfvars 리터럴 문자열이라 plan 시점에 확정된다(미상값 개입 없음).

# ── 1) cluster admin — 클러스터 전권 ────────────────────────
# 애드온(ArgoCD·KEDA·Karpenter·ALB Controller)을 클러스터 전역에 설치해야 하는 사람.
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(var.tags, { Name = "${local.name_prefix}-access-admin" })
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value

  # ⚠️ 전체 ARN 그대로 써야 한다. 짧은 이름으로는 동작하지 않는다.
  policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  # 엔트리가 먼저 있어야 정책을 붙일 수 있다.
  depends_on = [aws_eks_access_entry.admin]
}

# ── 2) namespace editor — 앱 네임스페이스 안에서만 ──────────
# 앱팀은 자기 파드의 로그를 보고 재시작하고 exec 로 들어가면 된다.
# 클러스터 전역 리소스(노드·CRD·다른 네임스페이스)는 건드릴 이유가 없다 → 주지 않는다.
#
# 실수로 애드온이나 남의 네임스페이스를 지우는 사고를 구조적으로 막는다.
# 나중에 누군가 admin 이 필요해지면 tfvars 에서 목록을 옮기면 된다(코드는 안 고친다).
resource "aws_eks_access_entry" "editor" {
  for_each = toset(var.cluster_editor_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(var.tags, { Name = "${local.name_prefix}-access-editor" })
}

resource "aws_eks_access_policy_association" "editor" {
  for_each = toset(var.cluster_editor_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value

  policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = var.editor_namespaces
  }

  depends_on = [aws_eks_access_entry.editor]
}
