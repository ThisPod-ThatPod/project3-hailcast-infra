# storage 모듈 - glue.tf
# OpenCost Cloud Costs(Level 2)가 CUR parquet 을 Athena 로 조회하려면 Glue 데이터 카탈로그가
# 그 파일들을 테이블로 알고 있어야 한다. Glue Crawler 가 S3 를 스캔해 스키마를 추론하고
# 카탈로그에 테이블을 채운다.
#
# AWS 가 CUR 정의를 만들 때 콘솔/문서용 CloudFormation 템플릿(crawler-cfn.yml)을 CUR 버킷에
# 같이 떨군다(규약서 §5-9). 이 파일은 그 템플릿의 핵심 리소스(Database·Crawler·크롤러 IAM 역할)를
# Terraform 으로 옮긴 것이다. 템플릿에 있는 Lambda 2개(S3 이벤트로 크롤러 자동 재실행 + 스택
# 생성 시 최초 1회 실행)는 옮기지 않는다 — Glue Crawler 자체 schedule 인자로 주기 실행이
# 되므로, Lambda 와 그 전용 IAM 역할 2개를 더 만들 이유가 없다(YAGNI · 팀 결정 2026-08-18).

data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  # Glue/Athena 데이터베이스 이름은 Hive 식별자라 하이픈을 못 쓴다.
  # §1 대원칙의 kebab-case 예외 — AWS 리소스 이름 규칙이 아니라 Hive 문법 제약이라 그렇다.
  glue_database_name = replace("${local.name_prefix}_cur", "-", "_")
}

resource "aws_glue_catalog_database" "cur" {
  name = local.glue_database_name
}

# 크롤러가 assume 할 역할. IRSA 가 아니다 — K8s 파드가 아니라 Glue 서비스가 이 역할을 쓴다
# (신뢰정책 principal 이 glue.amazonaws.com).
data "aws_iam_policy_document" "glue_crawler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_crawler" {
  name               = "${local.name_prefix}-glue-crawler-cur"
  assume_role_policy = data.aws_iam_policy_document.glue_crawler_assume.json

  tags = merge(var.tags, { Name = "${local.name_prefix}-glue-crawler-cur" })
}

# AWS 기본 템플릿(crawler-cfn.yml)은 s3:GetObject·PutObject 를 함께 준다. 크롤러는 스키마를
# 추론하려고 읽기만 하고 원본 CUR 파일에 쓰지 않는다 — PutObject 는 빼고 최소권한으로 좁힌다.
# 막히면(스키마 추론 실패) 크롤러 실행 로그에 원인이 남는다.
data "aws_iam_policy_document" "glue_crawler" {
  statement {
    sid    = "WriteCrawlerLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    # Glue 크롤러 로그 그룹은 항상 이 접두어로 생긴다(AWS 고정 규칙).
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
  }

  # AWS 기본 템플릿(crawler-cfn.yml)은 이 8개 액션을 Resource="*"로 준다. 그런데 여기 담긴
  # 액션은 전부 catalog·database·table 세 ARN 조합으로 인가된다(AWS Glue fine-grained access
  # 문서 기준) — irsa.tf 의 opencost ReadGlueCatalog 와 같은 패턴으로 좁힌다.
  statement {
    sid    = "UpdateCurCatalog"
    effect = "Allow"
    actions = [
      "glue:UpdateDatabase",
      "glue:UpdatePartition",
      "glue:CreatePartition",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:BatchCreatePartition",
      "glue:GetDatabase",
      "glue:GetTable",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:catalog",
      aws_glue_catalog_database.cur.arn,
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.cur.name}/*",
    ]
  }

  statement {
    sid       = "ReadCurData"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.cur.arn}/${var.cur_prefix}/hailcast-dev-cur/hailcast-dev-cur*"]
  }
}

resource "aws_iam_policy" "glue_crawler" {
  name        = "${local.name_prefix}-glue-crawler-cur-policy"
  description = "CUR Glue 크롤러 역할 정책 - CloudWatch 로그 쓰기 + 카탈로그 갱신 + CUR 원본 읽기(쓰기 없음)."
  policy      = data.aws_iam_policy_document.glue_crawler.json

  tags = merge(var.tags, { Name = "${local.name_prefix}-glue-crawler-cur-policy" })
}

resource "aws_iam_role_policy_attachment" "glue_crawler" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = aws_iam_policy.glue_crawler.arn
}

# 크롤러 본체. schedule 인자가 있어 별도 aws_glue_trigger 리소스가 필요 없다.
# 대상 경로는 crawler-cfn.yml 이 가리키는 실제 데이터 경로와 같다(리포트 이름이 폴더명으로
# 두 번 반복되는 것도 그대로 — cur/<리포트명>/<리포트명>/).
resource "aws_glue_crawler" "cur" {
  name          = "${local.name_prefix}-glue-crawler-cur"
  database_name = aws_glue_catalog_database.cur.name
  role          = aws_iam_role.glue_crawler.arn

  # 매일 03:00 UTC(KST 12:00). CUR 은 하루 단위로 갱신되고, 이 시간이면 전날치가 이미 반영돼 있다.
  schedule = "cron(0 3 * * ? *)"

  s3_target {
    path = "s3://${aws_s3_bucket.cur.id}/${var.cur_prefix}/hailcast-dev-cur/hailcast-dev-cur"
    # AWS 기본 템플릿과 같은 제외 목록 — 데이터 파일(parquet)이 아닌 부속 파일은 스키마 추론에서 뺀다.
    exclusions = ["**.json", "**.yml", "**.sql", "**.csv", "**.gz", "**.zip"]
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "DELETE_FROM_DATABASE"
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-glue-crawler-cur" })
}

# AWS가 CUR 정의와 함께 자동으로 만드는 상태 확인용 테이블. 크롤러가 못 만든다 — 스키마 추론
# 대상이 아니라 CUR 배달 서비스가 직접 관리하는 고정 스키마라서다. crawler-cfn.yml 이 이
# 테이블을 크롤러와 별개로 손수 정의해 둔 이유이기도 하다.
resource "aws_glue_catalog_table" "cur_status" {
  name          = "cost_and_usage_data_status"
  database_name = aws_glue_catalog_database.cur.name

  table_type = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.cur.id}/${var.cur_prefix}/hailcast-dev-cur/cost_and_usage_data_status/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "status"
      type = "string"
    }
  }
}
