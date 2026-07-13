locals {
  name_prefix = "${var.project}-${var.environment}"
}

# 1. S3 버킷 이름 뒤에 붙을 전역 고유 랜덤 접미사 생성
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 2. S3 버킷 생성 (관례 및 로컬 변수 적용)
resource "aws_s3_bucket" "model_bucket" {
  # .hex 대신 .id를 사용해도 동일하게 16진수 문자열이 들어갑니다. (VS Code 확장 프로그램 버그 예방)
  bucket        = "${local.name_prefix}-model-artifacts-${random_id.bucket_suffix.id}"
  force_destroy = true 

  tags = {
    Name = "${local.name_prefix}-model-artifacts"
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

# 5. 퍼블릭 액세스 차단 설정
resource "aws_s3_bucket_public_access_block" "model_bucket_public_block" {
  bucket = aws_s3_bucket.model_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}