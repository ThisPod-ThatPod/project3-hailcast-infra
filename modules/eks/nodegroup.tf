# eks 모듈 - nodegroup.tf
# system 관리형 노드그룹 + 전용 노드 SG + launch template. (M2)
#   - 이 노드그룹엔 '플랫폼'만 산다: CoreDNS·Karpenter·KEDA·ArgoCD·Prometheus 등(§5-3).
#     앱 파드는 Karpenter 가 0부터 띄우는 별도 노드로 감 → 이건 고정 베이스라인.
#   - launch template 를 쓰는 이유 2가지:
#       ① 전용 노드 SG 부착(RDS 가 5432 를 '노드 SG 에서 온 것만' 허용 — §5-5, M4 에서 연결)
#       ② 노드 EC2·EBS 에 비용 태그 직접 부착(관리형 노드그룹은 default_tags 가 인스턴스까지 전파 안 됨)

# ── 노드 SG (zero-inbound) ──
# 인바운드 규칙 0개. 노드↔노드·컨트롤플레인 통신은 EKS 클러스터 SG(self 허용)가 담당하고,
# 이 SG 는 'RDS 가 지목할 대상(§5-5)'이자 향후 타깃 규칙의 앵커 역할만 한다.
# (SG 는 '허용'만 하므로 zero-inbound 여도 클러스터 SG 의 노드간 허용을 막지 않는다.)
# ⚠️ 이 노드그룹이 클러스터 SG 를 다는 건 아래 LT 가 명시 부착하기 때문이다(:49-52).
#    Karpenter 노드는 LT 를 안 쓰고 태그로 찾은 SG 만 달아서, 클러스터 SG 에도
#    discovery 태그가 필요하다(cluster.tf · §6-1).
#
# ⚠️ karpenter.sh/discovery 태그가 없으면 앱이 DB 에 못 붙는다.
#    RDS 는 5432 를 '이 SG 를 단 놈'에게만 연다(§5-5). 그런데 정작 DB 를 쓰는 파드
#    (worker·call-api·predict)는 이 system 노드그룹이 아니라 Karpenter 가 띄우는 노드에 산다.
#    Karpenter 는 EC2NodeClass 의 securityGroupSelectorTerms 로 SG 를 태그 검색해 노드에 붙이므로,
#    이 태그가 빠지면 Karpenter 노드가 노드 SG 를 못 달고 → RDS 가 문을 안 열어준다.
#    (에러 없이 연결 타임아웃만 나서 원인 찾기가 어렵다 — §6-1 "빠지면 몇 시간 디버깅")
resource "aws_security_group" "node" {
  name        = "${local.name_prefix}-sg-eks-node"
  description = "EKS node/pod SG. No inbound rules (cluster SG covers node-to-node). Target of RDS 5432 ingress."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                     = "${local.name_prefix}-sg-eks-node"
    "karpenter.sh/discovery" = local.name_prefix # = hailcast-dev (§6-1 · 서브넷 태그와 같은 값)
  })
}

# egress 는 독립 리소스로(인라인/독립 혼용 금지 — data 모듈 RDS SG 와 동일 기조).
resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.node.id
  description       = "all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── Launch template ──
# image_id 를 지정하지 않으면 EKS 가 ami_type(AL2023)에 맞는 최적화 AMI 를 자동 주입한다.
# → AMI 관리는 EKS 에 맡기고, 우리는 SG·태그·IMDS 만 얹는다.
resource "aws_launch_template" "node" {
  name_prefix = "${local.name_prefix}-eks-system-"

  # 클러스터 SG(노드간·CP 통신) + 전용 노드 SG(RDS 지목 대상) 둘 다 부착.
  # LT 에 SG 를 지정하면 EKS 가 클러스터 SG 를 자동으로 안 붙이므로 여기서 명시한다.
  vpc_security_group_ids = [
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    aws_security_group.node.id,
  ]

  # IMDSv2 강제(자격증명 탈취형 SSRF 차단) + hop_limit=1 로 '파드의 IMDS 접근'을 차단한다.
  #   hop_limit=2 였다면 파드가 노드 IMDS 에 닿아 노드 역할(ECR-read·CNI·SSM)의 자격증명을
  #   훔쳐 쓸 수 있다 = IRSA 로 좁혀둔 권한을 우회. 이 노드에 사는 플랫폼 파드
  #   (Karpenter·ArgoCD·Prometheus)에도 그대로 적용된다.
  #   1 로 낮춰도 안 깨지는 이유: IRSA 는 IMDS 가 아니라 OIDC 웹아이덴티티 토큰을 쓰고,
  #   IMDS 가 실제로 필요한 CNI·kube-proxy 는 hostNetwork(노드 네트워크 네임스페이스)라 hop 1 로 닿는다.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # 노드 루트 볼륨 암호화 — RDS(storage_encrypted)와 저장 암호화 일관성. gp3 암호화는 무비용.
  block_device_mappings {
    device_name = "/dev/xvda" # AL2023 루트 디바이스
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # ⚠️ default_tags 는 'Terraform 리소스의 tags'에만 붙고 tag_specifications 엔 안 먹는다.
  #    → 노드 EC2·EBS 는 여기서 비용 태그(Project/Environment/ManagedBy)를 '명시적으로' 박아야
  #      FinOps 집계에서 안 샌다(비용런북 §3-2 A). 모듈 관례상 유일하게 tags 를 직접 다루는 곳.
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name        = "${local.name_prefix}-eks-system-node"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }
  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name        = "${local.name_prefix}-eks-system-vol"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-eks-system-lt" })
}

# ── system 관리형 노드그룹 (2× t3.large · 2AZ · AL2023) ──
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-eks-system-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids # 2 AZ → HA

  ami_type       = "AL2023_x86_64_STANDARD" # AL2 금지(1.33+), AL2023 최적화 AMI
  instance_types = var.node_instance_types

  scaling_config {
    min_size     = var.node_min_size     # 2 (HA)
    desired_size = var.node_desired_size # 2
    max_size     = var.node_max_size     # 3 (롤링·여유 상한)
  }

  update_config {
    max_unavailable = 1 # 업데이트 시 한 번에 한 노드만 교체
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    "hailcast.io/role" = "system"
  }

  # 노드 역할 정책(iam.tf, for_each)이 붙은 뒤 노드그룹을 만든다(클러스터 조인 실패 방지).
  depends_on = [aws_iam_role_policy_attachment.node]

  tags = merge(var.tags, { Name = "${local.name_prefix}-eks-system-ng" })

  lifecycle {
    # desired_size 는 운영 중 바뀔 수 있으니 drift 로 되돌리지 않는다.
    # min_size 도 무시한다 - 야간 절전 스케줄(§5-8)이 매일 min·desired 를 0↔2 로 바꾸는 소유자다.
    # 안 무시하면 야간(02~10시) apply 가 min 만 2로 되돌리려다 desired(0·ignore)와 어긋나
    # min > desired 로 UpdateNodegroupConfig 가 거부되거나, 최소한 plan 마다 diff 노이즈가 난다.
    ignore_changes = [scaling_config[0].desired_size, scaling_config[0].min_size]
  }
}
