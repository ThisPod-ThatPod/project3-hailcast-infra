# eks 모듈 - irsa.tf
# IRSA(IAM Roles for Service Accounts) = 파드마다 발급하는 '제한된 사원증'.
#
# 원리: 파드의 SA 토큰(JWT)을 STS 가 클러스터 OIDC provider 로 검증해 임시 자격증명을 내준다.
#   노드 역할(iam.tf 의 node role)을 쓰면 그 노드 위 '모든' 파드가 같은 권한을 공유하지만,
#   IRSA 는 SA 단위로 쪼개므로 최소권한이 성립한다.
# 그래서 신뢰정책(assume_role_policy)에 OIDC provider ARN 이 박히고 → 이 파일은 eks 모듈에 산다
#   (별도 security 모듈로 빼면 OIDC 의존 때문에 생성 순서가 꼬인다 = chicken-egg. 규약서 §5-3).
#
# ── 이 모듈은 S3·SQS·DynamoDB 를 '만들지' 않고 ARN 만 '받아쓴다' ──
# 정책이 지목할 리소스(storage·data 모듈 소관)는 아직 배선되지 않았다. 그렇다고 Resource="*" 로
# 열어두면 최소권한이 무너지므로, ARN 을 var 로 받고(variables.tf) envs/dev 가 스레딩하게 둔다.
# network 의 vpc_id 를 받아쓰는 것과 똑같은 패턴이다(§4) — 자식 모듈은 형제 모듈(module.storage)을
# 볼 수 없으므로, 값 전달은 루트를 거치는 이 방법뿐이다.
# 배선이 끝나면 envs/dev 에서 ARN 4개 + enable_app_irsa = true 만 채우면 이 파일은 손댈 일이 없다.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # 신뢰정책 condition 의 키는 issuer URL 에서 스킴을 뗀 호스트+경로 형태여야 한다.
  #   https://oidc.eks.ap-northeast-2.amazonaws.com/id/ABC → oidc.eks.ap-northeast-2.amazonaws.com/id/ABC
  # (STS 가 토큰의 iss 클레임을 이 문자열로 정규화해 대조한다)
  oidc_issuer_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")

  # 외부 ARN 이 필요 없는 2종 — 언제나 만든다.
  irsa_base = {
    lbctrl     = "kube-system:aws-load-balancer-controller"
    monitoring = "monitoring:monitoring-sa"
  }

  # ARN 배선이 끝나야 의미가 있는 5종.
  # 맵의 '키'는 역할명 접미사(§5-3)이자 manifests 가 irsa_role_arns 에서 뽑아 쓰는 키다.
  #   predict → hailcast-dev-irsa-predict. 키를 바꾸면 SA 애노테이션이 어긋나 '권한 없음'이 된다.
  # 값은 그 역할을 맬 SA("네임스페이스:이름") — manifests 의 serviceaccount.yaml 과 맺는 계약.
  #
  # ⚠️ forecast 역할은 없다(§5-3 · 2026-07-13 폐기). 결정 1 = predict 내장이라
  #    예측을 만들어 S3 에 쓰는 일을 predict 프로세스 안의 스케줄러가 한다.
  #    forecast-sa 를 달 파드가 없으므로 역할도 만들지 않는다. 그 권한은 predict 가 흡수했다.
  irsa_app = {
    predict    = "hailcast:predict-sa"
    "call-api" = "hailcast:call-api-sa"
    worker     = "hailcast:worker-sa"
    keda       = "keda:keda-operator"    # KEDA Helm 차트 기본 SA 명(§5-3)
    karpenter  = "kube-system:karpenter" # 관례상 kube-system
  }

  # for_each 의 '키'는 위 리터럴 문자열과 plan 시점에 확정된 불리언으로만 결정된다.
  # ARN '값'은 키 계산에 일절 개입하지 않는다 → `Invalid for_each argument` 회피(variables.tf 참고).
  irsa_service_accounts = merge(
    local.irsa_base,
    var.enable_app_irsa ? local.irsa_app : {},
  )
}

# ── 공통 신뢰정책 ───────────────────────────────────────────
# 'OIDC provider 가 서명했고(Federated), 토큰의 sub 가 이 SA 이고, aud 가 sts 인' 경우만 assume 허용.
#
# ⚠️ aud 조건을 빼면 안 된다. sub 만 검사하면 같은 OIDC issuer 를 신뢰하는 다른 대상(audience)용
#    토큰으로도 역할을 맬 수 있어 confused-deputy 가 열린다. 두 조건은 항상 한 쌍이다.
data "aws_iam_policy_document" "irsa_assume" {
  for_each = local.irsa_service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    # each.value 가 "kube-system:aws-load-balancer-controller" 이므로 아래가 곧
    # system:serviceaccount:kube-system:aws-load-balancer-controller 가 된다.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${each.value}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_service_accounts

  name               = "${local.name_prefix}-irsa-${each.key}" # hailcast-dev-irsa-lbctrl (§5-3)
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json

  tags = merge(var.tags, { Name = "${local.name_prefix}-irsa-${each.key}" })
}

# ── 1) lbctrl — AWS Load Balancer Controller ────────────────
# Ingress 를 보고 ALB 를 만들고 대상그룹에 파드 IP 를 등록하는 애드온(설치는 manifests/ArgoCD 소관).
#
# 정책 본문은 손으로 줄이지 않고 upstream 원본을 그대로 벤더링한다:
#   출처: kubernetes-sigs/aws-load-balancer-controller · docs/install/iam_policy.json
#   임의로 action 을 쳐내면 Ingress 조정(reconcile)이 특정 경로에서만 조용히 실패한다.
# 원본이 Resource="*" 인 statement 들은 대부분 elasticloadbalancing:*Tag 조건으로 좁혀져 있고,
# 컨트롤러가 클러스터 밖 LB 를 건드리지 않도록 upstream 이 조건을 설계해 두었다.
resource "aws_iam_policy" "lbctrl" {
  name        = "${local.name_prefix}-irsa-lbctrl-policy"
  description = "AWS Load Balancer Controller 공식 IAM 정책(upstream iam_policy.json 원본)."
  policy      = file("${path.module}/policies/aws-load-balancer-controller.json")

  tags = merge(var.tags, { Name = "${local.name_prefix}-irsa-lbctrl-policy" })
}

resource "aws_iam_role_policy_attachment" "lbctrl" {
  role       = aws_iam_role.irsa["lbctrl"].name
  policy_arn = aws_iam_policy.lbctrl.arn
}

# ── 2) monitoring — CloudWatch 읽기 ─────────────────────────
# Prometheus 사이드카/exporter 가 CloudWatch 지표를 긁어온다. 읽기 전용이라 AWS 관리형으로 충분하다.
# (ARN 은 상수 → 별도 커스텀 정책을 만들 이유가 없다. YAGNI)
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.irsa["monitoring"].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# ════════════════════════════════════════════════════════════════════
# 앱 5종 — enable_app_irsa = true 일 때만 (ARN 3종 배선 후 · 오답노트 DynamoDB 는 선택)
# ════════════════════════════════════════════════════════════════════

# ── 3) predict — 모델 읽기 · 예측 쓰기 · 오답노트 쓰기 · 큐 적체 '관측' ──
# 큐에 대해 조회만 준다. predict/app.py 의 /metrics·dashboard 가 적체를 보여줄 뿐,
# 스케일 결정은 KEDA 가 한다 → 송신·수신·삭제는 주지 않는다(§5-3).
#
# ⭐ S3 쓰기를 predict 가 갖는다 (2026-07-13 · 결정 1 = predict 내장).
#    예측을 만들어 predictions/latest.json 에 올리는 일을 별도 CronJob 이 아니라
#    predict 프로세스 안의 스케줄러가 한다(app predict/dependencies.py:49-50).
#    그래서 forecast 역할을 폐기하고 그 권한을 여기로 흡수했다(§5-3).
data "aws_iam_policy_document" "predict" {
  count = var.enable_app_irsa ? 1 : 0

  # ⚠️ 읽기 대상이 두 프리픽스인 게 중요하다. predict 는 models/ 만 읽는 게 아니라
  #    predictions/latest.json 도 읽는다(app predict/services/prediction_reader.py:24,28).
  #    models/ 로만 좁히면 scaler 가 예측 JSON 을 못 읽어 AccessDenied 로 죽는다.
  #    버킷 전체(/*)로 뭉뚱그리지 않고 둘을 명시한다 — 나중에 이 버킷에 다른 게 들어와도
  #    predict 가 그걸 읽지 않는다(§8).
  statement {
    sid     = "ReadModelsAndPredictions"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${var.model_bucket_arn}/models/*",
      "${var.model_bucket_arn}/predictions/*",
    ]
  }

  # ⭐ 쓰기는 predictions/ 로만 좁힌다. 이게 이 정책의 핵심이다.
  #    버킷 전체에 PutObject 를 주면 예측 스케줄러가 models/latest/model.txt 를
  #    덮어써 학습된 모델을 통째로 날릴 수 있다.
  #    ⚠️ latest.json 하나만 지목하면 안 된다 — 이력(predictions/history/*.json)도 함께 올라간다
  #       (app prediction_keep_history_in_s3 기본 true). 프리픽스 전체를 줘야 한다(§8).
  statement {
    sid       = "WritePredictionsOnly"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.model_bucket_arn}/predictions/*"]
  }

  # GetObject 만으로는 키 '목록'을 못 본다. 대상이 버킷 자체라 /* 를 붙이지 않는다.
  statement {
    sid       = "ListModelBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.model_bucket_arn]
  }

  # 오답노트는 '기록 전용'. 읽기·삭제·Scan 을 주면 재학습 데이터가 지워질 수 있다.
  #
  # ⭐ ARN 이 들어왔을 때만 붙인다. 테이블은 규약서 §5-4 에 확정돼 있으나 아직 아무 브랜치에도
  #    없고, 이 권한을 쓰는 앱 코드도 0건이다(§5-3 이 '미구현'이라 명시). 그런데 이걸 필수로
  #    강제하면 같은 스위치에 묶인 'karpenter' 역할까지 함께 막혀 노드 공급이 멈춘다.
  #    → 없으면 statement 를 만들지 않는다. 나중에 data 모듈이 테이블을 만들면 루트에서
  #      ARN 을 넘기는 것만으로 권한이 붙는다(이 파일은 고칠 게 없다).
  #
  # for_each 에 미상(unknown) ARN 이 와도 안전하다 — 판단하는 건 '값이 null 이냐'이고
  # 미상값은 null 이 아니므로 원소 1개짜리 리스트로 확정된다. 키가 값에서 파생되지 않는다.
  dynamic "statement" {
    for_each = var.prediction_log_table_arn == null ? [] : [var.prediction_log_table_arn]

    content {
      sid       = "WritePredictionLog"
      effect    = "Allow"
      actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
      resources = [statement.value]
    }
  }

  statement {
    sid       = "ObserveCallQueue"
    effect    = "Allow"
    actions   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [var.sqs_call_queue_arn]
  }
}

# ── 4) call-api — 큐에 '넣기만' ─────────────────────────────
# 최소권한의 요점: 콜 API 에 수신·삭제를 주면 자기가 쌓은 콜을 지울 수 있게 된다.
# 쓸 일 없는 권한은 사고만 낸다 → 워커와 역할을 쪼갠 이유(§5-3).
data "aws_iam_policy_document" "call_api" {
  count = var.enable_app_irsa ? 1 : 0

  statement {
    sid       = "SendCallToQueue"
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
    resources = [var.sqs_call_queue_arn]
  }
}

# ── 5) worker — 큐에서 '꺼내고 지우기만' ────────────────────
data "aws_iam_policy_document" "worker" {
  count = var.enable_app_irsa ? 1 : 0

  statement {
    sid       = "ConsumeCallQueue"
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueUrl"]
    resources = [var.sqs_call_queue_arn]
  }
}

# ── 6) keda — 큐 길이 조회 (반응형 스케일링의 생명줄) ───────
# ⚠️ 이게 없으면 반응형 스케일링이 '조용히' 죽는다. KEDA 의 aws-sqs-queue 트리거는 operator
#    자신이 GetQueueAttributes 를 호출해 큐 길이를 읽는데, 권한이 없으면 큐가 아무리 쌓여도
#    파드가 안 늘고 에러도 안 난다. manifests 의 TriggerAuthentication 이 이 역할을 참조한다.
#
# GetQueueUrl 이 빠진 건 오타가 아니다 — ScaledObject 가 queueURL 을 통째로 받으므로 이름→URL
# 조회가 필요 없다. 앱 3종과 달리 KEDA 만 예외다(§5-3).
data "aws_iam_policy_document" "keda" {
  count = var.enable_app_irsa ? 1 : 0

  statement {
    sid       = "ReadCallQueueLength"
    effect    = "Allow"
    actions   = ["sqs:GetQueueAttributes"]
    resources = [var.sqs_call_queue_arn]
  }
}

# 위 5종의 정책 생성·연결을 한 번에.
# for_each 키는 리터럴 + plan 시점 확정 불리언으로만 정해진다(정책 '본문'이 미상이어도 무방 —
# 미상이면 안 되는 건 '키'이지 '값'이 아니다).
locals {
  irsa_app_policies = var.enable_app_irsa ? {
    predict    = data.aws_iam_policy_document.predict[0].json
    "call-api" = data.aws_iam_policy_document.call_api[0].json
    worker     = data.aws_iam_policy_document.worker[0].json
    keda       = data.aws_iam_policy_document.keda[0].json
  } : {}

  # ⚠️ aws_iam_policy 의 description 은 AWS 에 수정 API 가 없어 Terraform 이 '정책을 지우고 다시 만든다'
  #    (Forces new resource). 재생성 순간 역할에서 정책이 떨어졌다 붙으므로 파드가 AccessDenied 를
  #    맞을 수 있다. 나중에 넣으면 비용이 생기고 지금 넣으면 공짜다 → 처음부터 채운다.
  #    (SG 의 description 과 같은 성질)
  irsa_app_policy_desc = {
    predict    = "predict-sa: S3 읽기(models+predictions) + predictions/ 쓰기 + DynamoDB 오답노트 기록 + SQS 큐 적체 조회."
    "call-api" = "call-api-sa: SQS 콜 큐 송신 전용(수신·삭제 없음)."
    worker     = "worker-sa: SQS 콜 큐 수신·삭제 전용(송신 없음)."
    keda       = "keda-operator: SQS 큐 길이 조회 전용(반응형 스케일 트리거)."
  }
}

resource "aws_iam_policy" "app" {
  for_each = local.irsa_app_policies

  name        = "${local.name_prefix}-irsa-${each.key}-policy"
  description = local.irsa_app_policy_desc[each.key]
  policy      = each.value

  tags = merge(var.tags, { Name = "${local.name_prefix}-irsa-${each.key}-policy" })
}

resource "aws_iam_role_policy_attachment" "app" {
  for_each = local.irsa_app_policies

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.app[each.key].arn
}

# ── 8) karpenter — 노드 공급 컨트롤러 ───────────────────────
# 정책 본문은 손으로 쓰지 않고 upstream 원본을 그대로 벤더링한다(lbctrl 과 같은 원칙):
#   출처: aws/karpenter-provider-aws · getting-started/.../cloudformation.yaml
#   조건절(aws:ResourceTag/kubernetes.io/cluster/<클러스터> = owned 등)이 촘촘해서 임의로 줄이면
#   노드가 안 뜨거나, 띄운 노드를 회수하지 못한다.
#
# upstream 이 정책을 6개로 '쪼개 둔' 것도 그대로 따른다 — IAM 관리형 정책엔 6,144자 상한이 있어
# 한 덩어리로 합치면 넘칠 수 있다. CloudFormation 의 ${AWS::Partition} 류 치환은 templatefile
# 변수로 옮겼다.
locals {
  karpenter_policy_files = var.enable_app_irsa ? toset([
    "node-lifecycle",     # EC2 생성·태깅·종료 (클러스터 태그로 범위 제한)
    "iam-integration",    # 노드 역할 PassRole + 인스턴스 프로파일 관리
    "eks-integration",    # eks:DescribeCluster (API 엔드포인트 탐색)
    "interruption",       # ⭐ Spot 중단 2분 경고 수신 — 없으면 중단 처리가 통째로 꺼진다(§5-4)
    "zonal-shift",        # AZ 장애 시 zonal shift 상태 조회
    "resource-discovery", # 인스턴스 타입·가격·AMI 조회 (읽기 전용)
  ]) : toset([])
}

resource "aws_iam_policy" "karpenter" {
  for_each = local.karpenter_policy_files

  name        = "${local.name_prefix}-irsa-karpenter-${each.key}-policy"
  description = "Karpenter 컨트롤러 정책(upstream cloudformation.yaml 원본) - ${each.key}."
  policy = templatefile("${path.module}/policies/karpenter-${each.key}.json.tftpl", {
    partition              = data.aws_partition.current.partition
    region                 = data.aws_region.current.region
    account_id             = data.aws_caller_identity.current.account_id
    cluster_name           = aws_eks_cluster.this.name
    node_role_arn          = aws_iam_role.node.arn
    interruption_queue_arn = var.karpenter_interruption_queue_arn
  })

  tags = merge(var.tags, { Name = "${local.name_prefix}-irsa-karpenter-${each.key}-policy" })
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  for_each = local.karpenter_policy_files

  role       = aws_iam_role.irsa["karpenter"].name
  policy_arn = aws_iam_policy.karpenter[each.key].arn
}
