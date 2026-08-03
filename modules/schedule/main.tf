# schedule 모듈 - 야간 절전 (EventBridge Scheduler · 규약서 §5-8)
# 켜 두기만 해도 나가는 노드·RDS 시간요금을 밤(기본 02~10시 KST)에 멈춘다.
# Lambda 없이 스케줄이 AWS API 를 직접 부른다(universal target).
#
# Karpenter 빈틈 (팀 결정 2026-07-21):
#    02:00 에 시스템 노드그룹이 0 이 되면 그 위의 Karpenter 컨트롤러가 갈 노드를 잃는다.
#    nodeAffinity 가 자기가 만든 노드를 배제해 살아 있는 Spot 노드로 옮겨가지도 못한다.
#    그래서 그 시점에 살아 있던 Spot 노드는 회수 주체가 없어 아침까지 남는다.
#    잔존해도 Spot 단가라 손실이 작고, 10:00 컨트롤러 부활 뒤 회수된다.
#    Lambda 로 강제 정리하는 확장은 하지 않는다(YAGNI). 상세는 규약서 §5-8.

data "aws_caller_identity" "current" {}

locals {
  name_prefix    = "${var.project_name}-${var.environment}"
  account_id     = data.aws_caller_identity.current.account_id
  rds_identifier = "${local.name_prefix}-rds-postgres" # 규약서 §5-4
  # 관리형 노드그룹 ARN 은 이름 뒤에 EKS 가 붙이는 식별자가 더 있다 → 와일드카드로 닫는다.
  nodegroup_arn = "arn:aws:eks:${var.aws_region}:${local.account_id}:nodegroup/${var.cluster_name}/${var.node_group_name}/*"
  rds_arn       = "arn:aws:rds:${var.aws_region}:${local.account_id}:db:${local.rds_identifier}"
}

# ── 스케줄 4개가 같이 쓰는 실행 역할. 대상 2개(해당 노드그룹·해당 RDS)로만 좁힌다 ──
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    # 다른 계정의 스케줄이 이 역할을 못 쓰게 계정을 못박는다(confused deputy 방지)
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name_prefix}-scheduler-night"
  description        = "EventBridge Scheduler role for nightly cost saving: scale system nodegroup and stop/start RDS. Targets are restricted to one nodegroup and one DB instance."
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "ScaleSystemNodegroup"
    effect    = "Allow"
    actions   = ["eks:UpdateNodegroupConfig"]
    resources = [local.nodegroup_arn]
  }

  statement {
    sid       = "StopStartRds"
    effect    = "Allow"
    actions   = ["rds:StopDBInstance", "rds:StartDBInstance"]
    resources = [local.rds_arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.name_prefix}-scheduler-night-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

# ── 밤: 노드 내리고 RDS 끈다 ──
resource "aws_scheduler_schedule" "night_stop_nodes" {
  name                         = "${local.name_prefix}-night-stop-nodes"
  description                  = "Scale system nodegroup to 0 for the night."
  schedule_expression          = var.stop_nodes_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:eks:updateNodegroupConfig"
    role_arn = aws_iam_role.scheduler.arn
    # 필드명은 Scheduler universal target 규격(PascalCase). EKS API 원형(camelCase)과 다르다.
    # 7/21 실측: camelCase 로 보내면 CreateSchedule 이 ValidationException(ClusterName 누락)을 낸다.
    input = jsonencode({
      ClusterName   = var.cluster_name
      NodegroupName = var.node_group_name
      ScalingConfig = {
        MinSize     = 0
        MaxSize     = var.node_max
        DesiredSize = 0
      }
    })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

resource "aws_scheduler_schedule" "night_stop_rds" {
  name                         = "${local.name_prefix}-night-stop-rds"
  description                  = "Stop RDS for the night."
  schedule_expression          = var.stop_rds_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    # Scheduler 규격은 DbInstanceIdentifier 다(Db 소문자 b · RDS API 원형 DBInstanceIdentifier 와 다름 · 7/21 실측).
    input = jsonencode({
      DbInstanceIdentifier = local.rds_identifier
    })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# ── 아침: RDS 먼저 켜고(기동 수 분) 노드를 복원한다 ──
resource "aws_scheduler_schedule" "morning_start_rds" {
  name                         = "${local.name_prefix}-morning-start-rds"
  description                  = "Start RDS before nodes come back."
  schedule_expression          = var.start_rds_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      DbInstanceIdentifier = local.rds_identifier
    })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

resource "aws_scheduler_schedule" "morning_start_nodes" {
  name                         = "${local.name_prefix}-morning-start-nodes"
  description                  = "Restore system nodegroup in the morning."
  schedule_expression          = var.start_nodes_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:eks:updateNodegroupConfig"
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      ClusterName   = var.cluster_name
      NodegroupName = var.node_group_name
      ScalingConfig = {
        MinSize     = var.node_restore_min
        MaxSize     = var.node_max
        DesiredSize = var.node_restore_desired
      }
    })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}
