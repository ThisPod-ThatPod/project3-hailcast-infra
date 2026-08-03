# data 모듈 - sqs_karpenter.tf
# Karpenter 중단(interruption) 큐 — 규약서 §5-4
#
# ⭐ 큐만 만들면 아무 일도 안 일어난다. 그것도 '조용히'.
#
#   AWS 📢 "이 Spot 인스턴스를 2분 뒤 회수합니다"        ← EventBridge 로 방송된다
#            ↓
#      EventBridge 규칙    ← ⚠️ 이게 없으면 여기서 끊긴다
#            ↓
#      SQS 큐 (hailcast-dev)
#            ↓
#      Karpenter 가 읽고 파드를 미리 다른 노드로 옮긴다
#
#   규칙이 없으면 큐가 영원히 비어 있고, Karpenter 는 에러 한 줄 없이 빈 큐만 계속 폴링한다
#   (karpenter v1.14.0 pkg/controllers/interruption/controller.go:97-103 — 메시지 0건이면 그냥 재큐).
#   그러다 Spot 회수가 오면 파드가 그냥 죽는다.
#   ※ 반대로 '큐 이름이 틀린' 경우는 시끄럽다("failed to create valid sqs provider" 로그).
#      조용히 죽는 쪽은 '규칙 누락' 이다 — 그래서 더 위험하다.
#
# 구성은 Karpenter 공식 CloudFormation(v1.14) 을 그대로 옮긴 것이다.
#   https://github.com/aws/karpenter-provider-aws/blob/v1.14.0/website/content/en/v1.14/getting-started/getting-started-with-karpenter/cloudformation.yaml

# ── 중단 큐 ────────────────────────────────────────────────
# 이름은 규약서 §5-4 확정값 `hailcast-dev`(= name_prefix)다. 클러스터 이름(hailcast-dev-eks)과
# 다르지만 문제되지 않는다 — Karpenter 는 settings.interruptionQueue 에 적힌 이름을 그대로
# GetQueueUrl 에 넘길 뿐, 클러스터명에서 큐명을 파생시키지 않는다(v1.14.0 pkg/providers/sqs/sqs.go).
# 공식 getting-started 가 클러스터명을 쓰는 건 '관례'이지 요구사항이 아니다.
#
# ⚠️ 그래서 배포팀이 Helm values 에 settings.interruptionQueue = hailcast-dev 를 '명시적으로'
#    넘겨야 한다. 안 넘기면 기본값이 빈 문자열이고, 그러면 중단 처리 컨트롤러가 아예 등록되지
#    않는다(v1.14.0 pkg/controllers/controllers.go — 값이 있을 때만 컨트롤러를 append). 규약서 §8 계약.
resource "aws_sqs_queue" "karpenter" {
  name = local.name_prefix # hailcast-dev (§5-4)

  # 공식 템플릿 값. Spot 경고는 '2분 뒤 회수' 라 5분 지난 메시지는 처리해도 의미가 없다.
  message_retention_seconds = 300

  # ⚠️ 반드시 SQS 관리형 SSE 를 쓴다. KMS 고객관리키(CMK)로 암호화하면 키 정책에
  #    events.amazonaws.com 의 kms:Decrypt·GenerateDataKey 를 따로 넣어야 하고,
  #    KMS '관리형' 키(alias/aws/sqs)는 키 정책을 못 고쳐서 EventBridge 가 아예 못 넣는다.
  #    공식 템플릿도 SqsManagedSseEnabled: true 다.
  sqs_managed_sse_enabled = true

  tags = merge(var.tags, { Name = local.name_prefix })
}

# ── 큐 정책 : EventBridge 가 이 큐에 넣을 수 있게 문을 열어준다 ──
# 이게 없으면 규칙은 도는데 SQS 가 메시지를 거부한다 → 역시 큐가 비어 있다.
data "aws_iam_policy_document" "karpenter_queue" {
  statement {
    sid    = "EC2InterruptionPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter.arn]
  }

  # 평문 HTTP 접근 차단(공식 템플릿의 DenyHTTP). TLS 로만 접근하게 강제한다.
  statement {
    sid    = "DenyHTTP"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter.arn]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id
  policy    = data.aws_iam_policy_document.karpenter_queue.json
}

# ── EventBridge 규칙 5종 ───────────────────────────────────
# 공식 CloudFormation 의 event pattern 을 그대로 옮겼다. 키는 리터럴 문자열이라
# for_each 에 안전하다(apply 시점에 이미 확정 — 미상값이 아니다).
#
# ⚠️ event pattern 에 클러스터·리소스 필터가 없다. 계정+리전의 '모든' EC2 이벤트가 이 큐로 온다.
#    Karpenter 는 자기 NodeClaim 이 없는 인스턴스의 메시지는 그냥 건너뛰고 지운다
#    (v1.14.0 pkg/controllers/interruption/utils.go — NodeClaim 0건이면 continue).
#    같은 계정에 클러스터가 여럿이면 클러스터마다 자기 큐 + 자기 규칙을 두면 서로 침범하지 않는다.
locals {
  karpenter_interruption_events = {
    "spot-interruption" = {
      source      = "aws.ec2"
      detail_type = "EC2 Spot Instance Interruption Warning"
      note        = "Spot 회수 2분 전 경고 — 이게 이 큐의 핵심이다"
    }
    "rebalance" = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance Rebalance Recommendation"
      note        = "회수 위험이 높아졌다는 사전 권고(경고보다 이르다)"
    }
    "instance-state-change" = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance State-change Notification"
      note        = "인스턴스가 실제로 종료·중지됐을 때"
    }
    "health-event" = {
      source      = "aws.health"
      detail_type = "AWS Health Event"
      note        = "AWS 측 하드웨어·유지보수로 노드가 영향받을 때"
    }
    "capacity-reservation-interruption" = {
      source      = "aws.ec2"
      detail_type = "EC2 Capacity Reservation Instance Interruption Warning"
      note        = "용량예약 인스턴스 중단. 우리는 용량예약을 안 쓰지만 공식 템플릿에 있어 맞춰 둔다"
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  name        = "${local.name_prefix}-karpenter-${each.key}"
  description = "Karpenter 중단 처리: ${each.value.note}"

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })

  tags = merge(var.tags, { Name = "${local.name_prefix}-karpenter-${each.key}" })
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = aws_cloudwatch_event_rule.karpenter_interruption

  rule      = each.value.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}
