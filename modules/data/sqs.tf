# data 모듈 - sqs.tf
# 콜 큐(hailcast-dev-call-queue) — 규약서 §5-4
#
# 이 큐가 이 프로젝트에서 두 가지 일을 한다.
#   ① 완충      : call-api 가 받은 콜을 쌓아두고, worker 가 자기 속도로 꺼내 처리한다.
#   ② 스케일 신호: KEDA 가 '큐에 몇 개 쌓였나'(ApproximateNumberOfMessages)를 보고
#                  worker 파드를 늘린다. 이게 '반응형 안전망'이다(3계층 중 2층).
#
# ⚠️ 이 큐가 없으면 시연 자체가 불가능하다. 시뮬레이터가 콜을 쌓을 곳이 없고,
#    큐가 비어 있으면 KEDA 가 늘릴 이유가 없어 선제 스케일링을 보여줄 수 없다.

# ── 콜 큐 ──────────────────────────────────────────────────
# 파라미터는 '앱 코드가 실제로 쓰는 값'에 맞춘다. 큐와 앱이 어긋나면
# 처리 중 메시지가 되살아나 중복 처리되거나, 폴링이 헛돈다.
resource "aws_sqs_queue" "call" {
  name = "${local.name_prefix}-call-queue"

  # 처리 중 메시지를 숨기는 시간. worker 가 이 시간 안에 처리를 못 끝내면
  # 메시지가 되살아나 '다른 파드가 같은 콜을 또 처리'한다.
  # 앱 기본값과 같은 30초로 맞춘다 (worker/config.py: sqs_visibility_timeout = 30).
  visibility_timeout_seconds = 30

  # Long Polling. 큐가 비어 있어도 20초까지 기다렸다 응답한다.
  # 짧게 두면 worker 가 '비었음' 응답을 초당 수십 번 받으며 요청 수만 늘린다(SQS 는 요청당 과금).
  # 앱도 같은 값을 쓴다 (worker/config.py: sqs_long_poll_seconds = 20).
  # ※ 앱은 ReceiveMessage 마다 WaitTimeSeconds 를 직접 넘기므로 큐 기본값을 덮어쓴다.
  #    여기 값은 '다른 무언가가 폴링할 때'의 안전한 기본값이다.
  receive_wait_time_seconds = 20

  # 처리되지 못한 메시지를 큐에 보관하는 기간(기본 4일). 데모엔 하루면 충분하다.
  # SQS 요금은 '요청 수' 기준이라 보관 기간은 비용에 영향이 없다 — 짧게 두는 건
  # 시연을 다시 돌릴 때 '어제 쌓인 콜'이 남아 큐 길이를 오염시키지 않게 하려는 것이다.
  message_retention_seconds = 86400 # 1일

  # AWS 관리형 서버측 암호화. 무료이고 키 관리가 필요 없다.
  # (KMS 고객관리키는 요청마다 KMS 요금이 붙는다 — 데모 규모엔 과하다.)
  sqs_managed_sse_enabled = true

  tags = merge(var.tags, { Name = "${local.name_prefix}-call-queue" })
}

# ⚠️ DLQ(Dead Letter Queue)는 일부러 만들지 않는다.
#    보통은 '계속 실패하는 메시지'가 무한 재수신되는 걸 막으려고 DLQ 를 붙인다.
#    그런데 앱 worker 가 이미 자체적으로 재수신 횟수를 세고 5회를 넘으면 FAILED 로
#    처리한다 (worker/config.py:14 — sqs_retry_count = 5, 주석에 '향후 DLQ 대상').
#    → 무한 루프가 생기지 않으므로 지금 DLQ 는 불필요하다(YAGNI).
#    앱이 나중에 '실패 메시지를 DLQ 로 보낸다'로 바꾸면 그때 추가한다.
