locals {
  name_prefix = "${var.project_name}-${var.environment}"
}


# 1. S3 버킷 이름 뒤에 붙을 전역 고유 랜덤 접미사 생성
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 2. S3 버킷 생성 (관례 및 로컬 변수 적용)
resource "aws_s3_bucket" "model_bucket" {
  bucket        = "${local.name_prefix}-model-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true # dev 환경의 원활한 teardown을 위해 true로 변경

  tags = {
    Name = "${local.name_prefix}-model-artifacts"
    # Environment, ManagedBy, Project는 provider default_tags에 의해 자동 적용되므로 중복 제거
  }
}

# 3. 버저닝 활성화
resource "aws_s3_bucket_versioning" "model_bucket_versioning" {
  bucket = aws_s3_bucket.model_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 4. 기본 서버 측 암호화 (SSE-S3 방식)
resource "aws_s3_bucket_server_side_encryption_configuration" "model_bucket_encryption" {
  bucket = aws_s3_bucket.model_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 4-1. lifecycle — 앱이 덮어쓰고 남긴 옛 버전을 정리한다.
#
# 이 버킷은 버저닝이 켜져 있어서(위 3번) 앱이 상태 파일을 다시 쓸 때마다 옛 버전이 남는다.
# 정리하지 않으면 destroy 가 그것까지 1000개씩 나눠 지워야 해서 오래 걸린다.
#
# expiration 은 현재 버전을 지우므로 프리픽스를 반드시 지정한다. 같은 버킷에 있는
# models/latest/model.pkl 이 지워지면 예측이 멈춘다.
# noncurrent_version_expiration 과 abort_incomplete_multipart_upload 는 현재 버전을 건드리지 않는다.
resource "aws_s3_bucket_lifecycle_configuration" "model_bucket_lifecycle" {
  bucket = aws_s3_bucket.model_bucket.id

  # 버저닝이 먼저 있어야 옛 버전 만료가 의미를 갖는다. provider 예제도 이 순서다.
  depends_on = [aws_s3_bucket_versioning.model_bucket_versioning]

  # 파드마다 자기 샤드 파일을 하나씩 쓴다. 파드가 없어져도 그 파일은 남는데 앱이 지우지 않는다.
  # expiration 이 그 남은 파일을 지운다. 돌고 있는 파드의 샤드는 2초마다 갱신돼서 안 걸린다.
  # 버전이 쌓이는 것은 그 아래 noncurrent 가 정리한다.
  rule {
    id     = "expire-traffic-shards"
    status = "Enabled"

    filter {
      prefix = "traffic/instances/"
    }

    expiration {
      days = var.traffic_shard_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }

  # predict 가 자기 상태를 적는 파일들. 최신 것은 두고 옛 버전만 지운다.
  # 버전이 가장 빨리 쌓이는 곳이다.
  rule {
    id     = "expire-dashboard-noncurrent"
    status = "Enabled"

    filter {
      prefix = "dashboard/"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }

  rule {
    id     = "expire-simulator-noncurrent"
    status = "Enabled"

    filter {
      prefix = "simulator/"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }

  # 업로드가 중간에 끊기면 조각이 남는다. 목록에는 안 보이는데 저장 요금은 붙는다.
  # 이 규칙은 그 조각만 지우므로 프리픽스를 안 걸어도 models/ 는 안전하다.
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# 5. 퍼블릭 액세스 차단 설정 (보안 강화 및 퍼블릭 노출 전면 차단)
resource "aws_s3_bucket_public_access_block" "model_bucket_public_block" {
  bucket = aws_s3_bucket.model_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}