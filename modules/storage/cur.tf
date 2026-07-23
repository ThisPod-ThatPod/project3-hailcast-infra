# storage 모듈 - cur.tf
# OpenCost Cloud Costs(Level 2)가 읽을 CUR(비용·사용량 보고서) 저장 버킷.
#
# CUR '정의' 자체는 Terraform 이 만들지 않는다. Budgets 와 같은 '방침'으로 IaC 밖에 둔다
# (같은 '이유'는 아니다 - Budgets 는 apply 역할이 Deny 하지만 cur: 는 Deny 목록에 없다 · 규약서 §5-9).
# 사람이 CLI 로 만든다. 명령은 규약서 §5-9 에 있다.
# 여기서 만드는 것은 그 정의가 파일을 떨어뜨릴 버킷과, AWS 청구 서비스가 그 버킷에 쓸 수 있게 하는
# 버킷 정책뿐이다. 정책이 없으면 CUR 정의 생성 자체가 실패한다.

locals {
  cur_bucket_name = "${local.name_prefix}-cur-${random_id.cur_suffix.hex}"
  account_id      = data.aws_caller_identity.current.account_id

  # CUR 정의와 Data Export 는 리전과 무관하게 us-east-1 에 만들어진다.
  # 버킷 정책의 SourceArn 조건이 그 ARN 을 가리켜야 한다.
  cur_source_arns = [
    "arn:aws:cur:us-east-1:${local.account_id}:definition/*",
    "arn:aws:bcm-data-exports:us-east-1:${local.account_id}:export/*",
  ]
}

data "aws_caller_identity" "current" {}

# model-artifacts 와 별개 접미사를 쓴다. 그 버킷 접미사는 콘솔 수동 정책에 박혀 있어
# (규약서 §5-9) 같이 묶으면 한쪽을 다시 만들 때 다른 쪽 정책까지 깨진다.
resource "random_id" "cur_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "cur" {
  bucket = local.cur_bucket_name

  # force_destroy 를 켜지 않는다. 비용 이력은 다시 만들 수 없고, CUR 첫 전달까지 24시간이 걸린다.
  # 파일이 들어 있으면 destroy 가 이 버킷에서 BucketNotEmpty 로 멈춘다 — 그게 의도한 방어선이다.
  #
  # ⚠️ prevent_destroy 는 쓰지 않는다. 그건 이 리소스 하나가 아니라 **plan 전체를 거부**해서
  #    (`Error: Instance cannot be destroyed`) EKS·NAT·RDS 를 포함해 아무것도 못 지우게 만든다.
  #    teardown 의 목적이 비싼 자원을 내리는 것이라 그 방식은 목적과 정면으로 부딪힌다.
  #    비우고 지우는 절차는 비용관리 §5 에 적는다.
  force_destroy = false

  tags = merge(var.tags, { Name = "${local.name_prefix}-cur" })
}

# 청구 상세가 들어 있다. 이 레포는 PUBLIC 이므로 노출 경로를 전부 막는다.
resource "aws_s3_bucket_public_access_block" "cur" {
  bucket = aws_s3_bucket.cur.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 버저닝은 켜지 않는다. CUR 은 같은 파일을 매일 덮어써서, 버전마다 요금이 붙는다.
# 비용 관리 도구가 비용을 만드는 것을 피한다.

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  # CUR 원본. Athena 가 스캔한 만큼 과금되므로 보관 기간을 정해 둔다.
  rule {
    id     = "expire-cur-data"
    status = "Enabled"

    filter {
      prefix = "${var.cur_prefix}/"
    }

    expiration {
      days = var.cur_retention_days
    }
  }

  # Athena 쿼리 결과. OpenCost 가 주기적으로 조회하므로 놔두면 계속 쌓인다.
  rule {
    id     = "expire-athena-results"
    status = "Enabled"

    filter {
      prefix = "${var.athena_results_prefix}/"
    }

    expiration {
      days = var.athena_results_retention_days
    }
  }

  # 실패한 멀티파트 업로드 조각은 보이지 않는 채로 과금된다.
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# AWS 청구 서비스가 이 버킷에 쓸 수 있게 한다.
#   - 소유자 확인: s3:GetBucketAcl · s3:GetBucketPolicy (버킷 자체)
#   - 배달       : s3:PutObject (버킷/*)
# 출처: https://docs.aws.amazon.com/cur/latest/userguide/cur-s3.html
#
# 두 서비스 주체를 함께 넣는다. 레거시 CUR 은 billingreports, Data Exports(CUR 2.0)는
# bcm-data-exports 로 온다. 콘솔에서 어느 경로로 만들지는 사람이 정하므로 둘 다 열어 둔다.
data "aws_iam_policy_document" "cur_bucket" {
  statement {
    sid    = "AllowBillingServiceBucketRead"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "billingreports.amazonaws.com",
        "bcm-data-exports.amazonaws.com",
      ]
    }

    actions   = ["s3:GetBucketAcl", "s3:GetBucketPolicy"]
    resources = [aws_s3_bucket.cur.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    # SourceArn 값에 와일드카드가 들어가므로 ArnLike 를 쓴다.
    # AWS 문서의 기본 정책은 같은 값에 StringEquals 를 쓴다. 어느 쪽이 맞는지는 서비스가 실제로
    # 넘기는 SourceArn 값에 달렸는데 그 값을 확인하지 못했다. ArnLike 는 두 경우를 다 덮는
    # 상위집합이라 이쪽을 골랐다. 배달이 확인되면 좁혀도 된다.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = local.cur_source_arns
    }
  }

  statement {
    sid    = "AllowBillingServicePutObject"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "billingreports.amazonaws.com",
        "bcm-data-exports.amazonaws.com",
      ]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cur.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = local.cur_source_arns
    }
  }
}

resource "aws_s3_bucket_policy" "cur" {
  bucket = aws_s3_bucket.cur.id
  policy = data.aws_iam_policy_document.cur_bucket.json

  # 퍼블릭 차단을 먼저 세운 뒤 정책을 붙인다. 이 정책은 서비스 주체 대상이라 퍼블릭 판정 대상이
  # 아니지만, 두 리소스 사이에 참조가 없어 terraform 이 순서를 보장하지 않는다. 명시해 둔다.
  depends_on = [aws_s3_bucket_public_access_block.cur]
}
