# eks 모듈 - cluster.tf
# EKS 컨트롤플레인 본체 + IRSA 전제인 OIDC provider.
#   - 컨트롤플레인 역할(iam.tf)·network 의 private 서브넷을 소비한다.
#   - 엔드포인트: 하이브리드(public+private). public 허용 대역은 변수(기본 0.0.0.0/0, 데모).
#     ⚠️ 0.0.0.0/0 은 '네트워크 도달 가능'일 뿐 — 실제 조작은 여전히 IAM+RBAC 를 통과해야 한다.
#     운영/조임 시 envs 에서 public_access_cidrs = ["<내IP>/32"] 로 오버라이드.

resource "aws_eks_cluster" "this" {
  name     = "${local.name_prefix}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    # 컨트롤플레인 ENI 는 프라이빗 서브넷(2개 AZ)에 배치. 노드도 여기(karpenter discovery 태그).
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  # 접근제어는 최신 Access Entry(API) 방식. 클러스터 생성자(apply 주체)에게 admin 을 자동 부여해
  # 락아웃을 막는다. 추가 관리자 access entry 는 노드그룹 PR(M2)에서 얹는다.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # 컨트롤플레인 역할에 정책이 붙은 뒤 클러스터를 만든다(생성 시 권한 경쟁 방지).
  depends_on = [aws_iam_role_policy_attachment.cluster]

  tags = merge(var.tags, { Name = "${local.name_prefix}-eks" })
}

# ── OIDC provider (IRSA 전제) ──
# 클러스터가 발급한 issuer 로 IAM OIDC provider 를 만들어야 파드가 IRSA(제한된 사원증)를 받는다.
# issuer 의 TLS 지문을 동적으로 계산(cicd 모듈의 tls 패턴 재사용) → 지문 하드코딩/만료 걱정 없음.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${local.name_prefix}-eks-oidc" })
}
