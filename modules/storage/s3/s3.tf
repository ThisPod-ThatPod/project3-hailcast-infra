# 1. S3 버킷 이름 뒤에 붙을 전역 고유 랜덤 접미사 생성
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 2. S3 버킷 생성 (사전 정의 규칙 적용)
resource "aws_s3_bucket" "model_bucket" {
  bucket        = "hailcast-dev-model-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = false # 운영 환경 데이터 보호를 위해 false로 유지

  tags = {
    Name        = "hailcast-dev-model-artifacts"
    Environment = "dev"
    ManagedBy   = "terraform"
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

# 5. 퍼블릭 액세스 차단 설정 (보안 강화 및 퍼블릭 노출 전면 차단)
resource "aws_s3_bucket_public_access_block" "model_bucket_public_block" {
  bucket = aws_s3_bucket.model_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}