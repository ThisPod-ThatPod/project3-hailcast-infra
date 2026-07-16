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
# network 의 vpc_id 를 받아쓰는 것과 똑같은 패턴이다(§4). 자식 모듈은 형제 모듈(module.storage)을
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

  # 외부 ARN 이 필요 없는 2종. 언제나 만든다.
  irsa_base = {
    lbctrl     = "kube-system:aws-load-balancer-controller"
    monitoring = "monitoring:monitoring-sa"
  }

  # ARN 배선이 끝나야 의미가 있는 5종.
  # 맵의 '키'는 역할명 접미사(§5-3)이자 manifests 가 irsa_role_arns 에서 뽑아 쓰는 키다.
  #   predict → hailcast-dev-irsa-predict. 키를 바꾸면 SA 애노테이션이 어긋나 '권한 없음'이 된다.
  # 값은 그 역할을 맬 SA("네임스페이스:이름"). manifests 의 serviceaccount.yaml 과 맺는 계약.
  #
  # forecast 역할은 없다(§5-3 · 2026-07-13 폐기). 결정 1 = predict 내장이라
  #    예측을 만들어 S3 에 쓰는 일을 predict 프로세스 안의 스케줄러가 한다.
  #    forecast-sa 를 달 파드가 없으므로 역할도 만들지 않는다. 그 권한은 predict 가 흡수했다.
  irsa_app = {
    predict        = "hailcast:predict-sa"
    "call-api"     = "hailcast:call-api-sa"
    worker         = "hailcast:worker-sa"
    "weather-cron" = "hailcast:weather-cron-sa"
    keda           = "keda:keda-operator"                # KEDA Helm 차트 기본 SA 명(§5-3)
    karpenter      = "kube-system:karpenter"             # 관례상 kube-system
    simulator      = "hailcast:simulator-sa"             # s3 백엔드로 simulator/status.json 쓰기(§5-3)
    eso            = "external-secrets:external-secrets" # ESO 컨트롤러 SA(Helm 기본값). RDS 시크릿 읽기
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
# aud 조건을 빼면 안 된다. sub 만 검사하면 같은 OIDC issuer 를 신뢰하는 다른 대상(audience)용
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

# ── 1) lbctrl - AWS Load Balancer Controller ────────────────
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

# ── 2) monitoring - CloudWatch 읽기 ─────────────────────────
# Prometheus 사이드카/exporter 가 CloudWatch 지표를 긁어온다. 읽기 전용이라 AWS 관리형으로 충분하다.
# (ARN 은 상수 → 별도 커스텀 정책을 만들 이유가 없다. YAGNI)
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.irsa["monitoring"].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# ════════════════════════════════════════════════════════════════════
# 앱 6종. enable_app_irsa = true 일 때만 (ARN 3종 배선 후 · 오답노트 DynamoDB 는 선택)
#
# 앱이 DB 를 빼고 S3 를 유일한 진실원천으로 재설계했다(app common/core/store.py:2
#    "DB를 뺀 이번 재설계"). 그래서 콜 기록·트래픽 집계·스케일 이력·대시보드까지 전부
#    이 버킷 하나를 지나간다. 아래 프리픽스 표가 그 결과다(app common/core/constants.py).
#
#   프리픽스              | predict | call-api | worker | weather-cron
#   ----------------------|---------|----------|--------|-------------
#   models/*              |  읽기   |    -     |   -    |     -
#   predictions/*         |  읽기+쓰기 |  -     |   -    |     -
#   weather/*             |  읽기   |    -     |   -    |   쓰기
#   traffic/instances/*   |  읽기   |   쓰기   |   -    |     -
#   dashboard/*           |  읽기+쓰기 |  -     |   -    |     -
#   scaling/*             |  읽기+쓰기 |  -     |   -    |     -
#   calls/*               |    -    |   읽기   | 읽기+쓰기 |   -
#
# 앱의 FileStore 는 read 하기 전에 exists() 를 먼저 부르고, exists() 는 head_object 다
#    (app common/aws/s3_adapter.py:95-100 · head_object 는 :97). HeadObject 는 s3:GetObject 권한으로 인가되므로
#    별도 action 이 필요 없다. 읽는 프리픽스에 GetObject 만 있으면 된다.
#
# 읽기 권한을 빠뜨리면 'AccessDenied' 로 안 보인다. '파일 없음' 으로 둔갑한다.
#    exists() 가 모든 ClientError 를 삼키고 False 를 반환하기 때문이다(s3_adapter.py:98-100).
#    그래서 증상이 "weather forecast CSV empty/missing" 처럼 데이터 문제로 뜬다
#    (app predict/services/prediction_service.py:77). 권한 문제를 데이터 문제로 착각하게 된다.
#    → 아래 프리픽스 표를 IAM 정책의 '정답지' 로 삼아라. 로그는 원인을 안 알려준다.
# 운영에서 CreateBucket 은 안 나간다. 어댑터의 auto_create 가 전 서비스 기본 false 이고
#    (app */config.py 의 s3_auto_create_bucket), 버킷은 IaC 가 소유한다 → s3:CreateBucket 불필요.
# ════════════════════════════════════════════════════════════════════

# ── 3) predict - 예측·집계·스케일의 중심. 이 버킷을 가장 넓게 쓴다 ──
# 큐에 대해서는 조회만 준다. predict/app.py 의 /metrics·dashboard 가 적체를 보여줄 뿐,
# 스케일 결정은 KEDA 가 한다 → 송신·수신·삭제는 주지 않는다(§5-3).
#
# S3 쓰기를 predict 가 갖는다 (2026-07-13 · 결정 1 = predict 내장).
#    예측을 만들어 predictions/latest.json 에 올리는 일을 별도 CronJob 이 아니라
#    predict 프로세스 안의 스케줄러가 한다(app predict/dependencies.py:52-58 ForecastScheduler · :116-117 ScalingScheduler).
#    그래서 forecast 역할을 폐기하고 그 권한을 여기로 흡수했다(§5-3).
data "aws_iam_policy_document" "predict" {
  count = var.enable_app_irsa ? 1 : 0

  # 읽기와 쓰기를 '다른 프리픽스 집합'으로 자르는 게 이 정책의 핵심이다.
  #    models/ 가 읽기 그룹에만 있고 쓰기 그룹엔 없다. 그래야 예측 스케줄러가
  #    models/latest/model.pkl 을 덮어써 학습된 모델을 날리는 일이 원천봉쇄된다.
  #    (파일명은 model.txt 가 아니라 model.pkl 이다 · app model_loader.py:30 실측.
  #     규약서가 한때 model.txt 라 적었으나 앱에 그 문자열은 0건이다. IAM 은 프리픽스로
  #     자르므로 정책 자체는 파일명과 무관하다.)
  #
  # 읽기 전용 프리픽스 셋. 남이 쓴 것을 predict 가 받아 읽기만 한다.
  #   models/*            ML 학습 산출물         (app predict/ml_runtime/model_loader.py)
  #   weather/*           weather-cron 이 쓴 CSV (app predict/services/prediction_service.py:130 · health_service.py:73)
  #   traffic/instances/* call-api 파드별 샤드   (app predict/services/traffic_aggregator_service.py:46)
  statement {
    sid     = "ReadOnlyPrefixes"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${var.model_bucket_arn}/models/*",
      "${var.model_bucket_arn}/weather/*",
      "${var.model_bucket_arn}/traffic/instances/*",
      "${var.model_bucket_arn}/simulator/*",
    ]
  }

  # 읽기+쓰기 프리픽스 셋. predict 가 스스로 만들어 놓고 스스로 다시 읽는 상태 파일들.
  #   predictions/*  예측 JSON·CSV + 이력  (쓰기 prediction_service.py:157-177 / 읽기 prediction_reader.py:26)
  #                  latest.json 하나로 좁히면 안 된다. history/<타임스탬프>.json 이 함께 올라간다
  #                     (prediction_keep_history_in_s3 기본 true). 프리픽스 전체를 줘야 한다(§8).
  #   dashboard/*    트래픽 집계·이력·파드 이력 (traffic_aggregator_service.py:30,64,67 · pod_forecast_service.py:84,97)
  #   scaling/*      스케일 이벤트 이력·직전 이벤트 (scaler_service.py:72,238-239)
  statement {
    sid     = "ReadWritePrefixes"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "${var.model_bucket_arn}/predictions/*",
      "${var.model_bucket_arn}/dashboard/*",
      "${var.model_bucket_arn}/scaling/*",
    ]
  }

  # ListBucket 이 없으면 트래픽 집계가 통째로 죽는다.
  #    predict 는 traffic/instances/ 아래 '파드마다 하나씩' 쌓인 샤드를 list_keys() 로 훑어
  #    합산한다(app traffic_aggregator_service.py:46 → s3_adapter.py:90 list_objects_v2).
  #    프리픽스 아래를 훑는 동작이라 GetObject 로는 안 된다.
  #    대상이 '버킷 자체'라 /* 를 붙이지 않는다. 붙이면 목록 조회가 인가되지 않는다.
  #    조건이 없으면 버킷 전체를 목록 조회할 수 있어 s3:prefix 로 좁힌다.
  #    StringEquals 로 걸면 안 된다. 앱이 보내는 실값이 "traffic/instances/" 라 리터럴 비교가 안 맞는다.
  #    막히면 파드는 안 죽는다. 스케줄러가 모든 예외를 삼켜 로그와 failure_count 로만 남기므로
  #    (app common/core/scheduler.py:67-73), 겉은 Healthy·200 인데 dashboard/traffic.json 이 갱신을 멈춘다.
  #    증상이 "권한 오류"가 아니라 "그래프가 안 움직임"으로 보인다.
  statement {
    sid       = "ListBucketForTrafficShards"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.model_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["traffic/instances/*"]
    }
  }

  # 오답노트는 '기록 전용'. 읽기·삭제·Scan 을 주면 재학습 데이터가 지워질 수 있다.
  #
  # ARN 이 들어왔을 때만 붙인다. 테이블은 규약서 §5-4 에 확정돼 있으나 아직 아무 브랜치에도
  #    없고, 이 권한을 쓰는 앱 코드도 0건이다(§5-3 이 '미구현'이라 명시). 그런데 이걸 필수로
  #    강제하면 같은 스위치에 묶인 'karpenter' 역할까지 함께 막혀 노드 공급이 멈춘다.
  #    → 없으면 statement 를 만들지 않는다. 나중에 data 모듈이 테이블을 만들면 루트에서
  #      ARN 을 넘기는 것만으로 권한이 붙는다(이 파일은 고칠 게 없다).
  #
  # 미상(unknown) ARN 이 와도 plan 은 죽지 않는다. 다만 이유를 정확히 알아 둬라.
  #    `unknown == null` 은 false 가 아니라 unknown 이다(TF 1.15.5 실측 · 조건식 결과가
  #    "known after apply" 로 나온다). 즉 이 리스트는 '확정'되지 않는다.
  #
  #    그런데도 안전한 진짜 이유는 둘이다.
  #    ① dynamic 블록은 '리소스 레벨' for_each 와 달리 미상 for_each 를 허용한다.
  #       블록 전체가 unknown 이 되고 data source read 가 apply 로 미뤄진다(실측: plan 성공).
  #    ② 이 문서를 소비하는 aws_iam_policy.app 의 for_each '키' 는 리터럴이라
  #       미상값이 키 계산에 개입하지 않는다. 미상이면 안 되는 건 '키'이지 '값'이 아니다.
  #
  #    이 논리를 '리소스 레벨' for_each/count 에 그대로 옮기지 마라.
  #       거기서는 `Invalid for_each argument` 로 plan 이 죽는다(그게 위 locals 가 피하는 것).
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

# ── 4) call-api - 큐에 '넣기만' + 콜 조회(읽기) + 트래픽 샤드(쓰기) ──
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

  # GET /call/{id} 가 worker 의 처리 결과를 읽는다(app call-api/services/call_service.py:59).
  # 쓰는 쪽은 worker 다 → call-api 는 '읽기만'. 여기에 PutObject 를 주면 콜 API 가
  # 처리 상태를 스스로 조작할 수 있게 된다.
  statement {
    sid       = "ReadCallRecords"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.model_bucket_arn}/calls/*"]
  }

  # 파드마다 자기 몫의 콜 수를 10초마다 샤드 파일로 쓴다(app call-api/services/traffic_counter.py:34).
  # predict 가 이걸 모아 합산한다. 읽는 쪽은 predict 라 call-api 는 '쓰기만' 있으면 된다.
  statement {
    sid       = "WriteTrafficShard"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.model_bucket_arn}/traffic/instances/*"]
  }
}

# ── 5) worker - 큐에서 '꺼내고 지우기만' + 콜 기록 저장 ─────
data "aws_iam_policy_document" "worker" {
  count = var.enable_app_irsa ? 1 : 0

  statement {
    sid       = "ConsumeCallQueue"
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueUrl"]
    resources = [var.sqs_call_queue_arn]
  }

  # 콜 기록의 '쓰는 쪽'. 읽기가 함께 필요한 건 멱등 때문이다. 같은 메시지를 다시 받으면
  # (visibility timeout 만료 등) 이미 저장됐는지 먼저 읽어 보고, 있으면 다시 쓰지 않는다
  # (app worker/services/worker_service.py:92 읽기 · :115 쓰기 · 키 조립 :88). 읽기를 빼면 재수신 때마다 덮어쓴다.
  statement {
    sid       = "ReadWriteCallRecords"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.model_bucket_arn}/calls/*"]
  }
}

# ── 6) weather-cron - 날씨 CSV 쓰기 '만' ────────────────────
# 2026-07-14 신설. 예측 파이프라인의 출발점이라, 이 역할이 없으면 CSV 가 안 올라가고
#    predict 가 그걸 못 읽어 예측이 통째로 안 된다(app predict/services/prediction_service.py:77
#    가 "weather forecast CSV empty/missing" 로 죽는다).
#
# 이 서비스는 S3 말고는 AWS 를 만지지 않는다(SQS·DynamoDB 사용 0건 · 실측). 읽기 호출도 0건이라
# GetObject 도 주지 않는다. 매 주기 CSV 를 통째로 덮어쓴다(app weather-cron/services/weather_service.py:58).
# 그래서 역할이 이렇게 얇다.
data "aws_iam_policy_document" "weather_cron" {
  count = var.enable_app_irsa ? 1 : 0

  statement {
    sid       = "WriteWeatherCsv"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.model_bucket_arn}/weather/*"]
  }
}

# ── 7) keda - 큐 길이 조회 (반응형 스케일링의 생명줄) ───────
# 이게 없으면 반응형 스케일링이 '조용히' 죽는다. KEDA 의 aws-sqs-queue 트리거는 operator
#    자신이 GetQueueAttributes 를 호출해 큐 길이를 읽는데, 권한이 없으면 큐가 아무리 쌓여도
#    파드가 안 늘고 에러도 안 난다. manifests 의 TriggerAuthentication 이 이 역할을 참조한다.
#
# GetQueueUrl 이 빠진 건 오타가 아니다. ScaledObject 가 queueURL 을 통째로 받으므로 이름→URL
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

# ── 9) simulator - 시뮬레이터 상태 파일 쓰기 만 ──────────────
# K8s 에 s3 백엔드로 뜨면 2초마다 simulator/status.json 을 S3 에 쓴다
# (app simulator/schedulers/status_scheduler.py). 그 프리픽스 쓰기 하나면 된다.
data "aws_iam_policy_document" "simulator" {
  count = var.enable_app_irsa ? 1 : 0

  statement {
    sid       = "WriteSimulatorStatus"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.model_bucket_arn}/simulator/*"]
  }
}

# ── 10) eso - External Secrets 컨트롤러가 RDS 비번 시크릿을 읽는다 ──
# RDS 자동생성 시크릿 하나만 GetSecretValue 한다. ESO 가 그 값을 hailcast 네임스페이스에
# K8s Secret 으로 복제하면 call-api·worker·predict 가 환경변수로 읽는다(§5-4).
# AWS 를 직접 부르는 앱 파드는 없다. 이 컨트롤러 하나뿐이다.
data "aws_iam_policy_document" "eso" {
  count = var.enable_app_irsa ? 1 : 0

  statement {
    sid       = "ReadRdsMasterSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.rds_master_secret_arn]
  }
}

# 위 7종의 정책 생성·연결을 한 번에.
# for_each 키는 리터럴 + plan 시점 확정 불리언으로만 정해진다(정책 '본문'이 미상이어도 무방.
# 미상이면 안 되는 건 '키'이지 '값'이 아니다).
locals {
  irsa_app_policies = var.enable_app_irsa ? {
    predict        = data.aws_iam_policy_document.predict[0].json
    "call-api"     = data.aws_iam_policy_document.call_api[0].json
    worker         = data.aws_iam_policy_document.worker[0].json
    "weather-cron" = data.aws_iam_policy_document.weather_cron[0].json
    keda           = data.aws_iam_policy_document.keda[0].json
    simulator      = data.aws_iam_policy_document.simulator[0].json
    eso            = data.aws_iam_policy_document.eso[0].json
  } : {}

  # aws_iam_policy 의 description 은 AWS 에 수정 API 가 없어 Terraform 이 '정책을 지우고 다시 만든다'
  #    (Forces new resource). 재생성 순간 역할에서 정책이 떨어졌다 붙으므로 파드가 AccessDenied 를
  #    맞을 수 있다. 나중에 넣으면 비용이 생기고 지금 넣으면 공짜다 → 처음부터 채운다.
  #    (SG 의 description 과 같은 성질)
  irsa_app_policy_desc = {
    predict        = "predict-sa: S3 읽기(models·weather·traffic·simulator) + 읽기쓰기(predictions·dashboard·scaling) + ListBucket + DynamoDB 오답노트 기록 + SQS 큐 적체 조회."
    "call-api"     = "call-api-sa: SQS 콜 큐 송신 + S3 calls/ 읽기 + traffic/instances/ 쓰기(수신·삭제 없음)."
    worker         = "worker-sa: SQS 콜 큐 수신·삭제 + S3 calls/ 읽기쓰기(송신 없음)."
    "weather-cron" = "weather-cron-sa: S3 weather/ 쓰기 전용(읽기 없음 · SQS·DynamoDB 없음)."
    keda           = "keda-operator: SQS 큐 길이 조회 전용(반응형 스케일 트리거)."
    simulator      = "simulator-sa: S3 simulator/ 쓰기 전용(status.json)."
    eso            = "external-secrets: RDS 자동생성 비번 시크릿 GetSecretValue 전용."
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

# ── 8) karpenter - 노드 공급 컨트롤러 ───────────────────────
# 정책 본문은 손으로 쓰지 않고 upstream 원본을 그대로 벤더링한다(lbctrl 과 같은 원칙):
#   출처: aws/karpenter-provider-aws · getting-started/.../cloudformation.yaml
#   조건절(aws:ResourceTag/kubernetes.io/cluster/<클러스터> = owned 등)이 촘촘해서 임의로 줄이면
#   노드가 안 뜨거나, 띄운 노드를 회수하지 못한다.
#
# upstream 이 정책을 6개로 '쪼개 둔' 것도 그대로 따른다. IAM 관리형 정책엔 6,144자 상한이 있어
# 한 덩어리로 합치면 넘칠 수 있다. CloudFormation 의 ${AWS::Partition} 류 치환은 templatefile
# 변수로 옮겼다.
locals {
  karpenter_policy_files = var.enable_app_irsa ? toset([
    "node-lifecycle",     # EC2 생성·태깅·종료 (클러스터 태그로 범위 제한)
    "iam-integration",    # 노드 역할 PassRole + 인스턴스 프로파일 관리
    "eks-integration",    # eks:DescribeCluster (API 엔드포인트 탐색)
    "interruption",       # Spot 중단 2분 경고 수신. 없으면 중단 처리가 통째로 꺼진다(§5-4)
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
