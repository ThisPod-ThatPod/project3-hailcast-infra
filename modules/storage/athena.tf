# storage 모듈 - athena.tf
# OpenCost 가 Athena 로 CUR 을 조회할 때 쓸 workgroup. 결과는 이미 예약해 둔
# athena-results/ 프리픽스(§5-2)에 쌓이고, cur.tf 의 lifecycle 규칙이 7일 뒤 지운다.

resource "aws_athena_workgroup" "opencost" {
  name = "${local.name_prefix}-opencost"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false # 쿼리 지표까지는 필요 없다(YAGNI)

    result_configuration {
      output_location = "s3://${aws_s3_bucket.cur.id}/${var.athena_results_prefix}/"
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-opencost" })
}
