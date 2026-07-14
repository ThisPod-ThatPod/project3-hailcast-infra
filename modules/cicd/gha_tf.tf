# cicd 모듈 - gha_tf.tf
# GitHub Actions 가 terraform 을 돌릴 때 쓰는 역할 2종 — 규약서 §5-6
#
# ⭐ 왜 역할을 둘로 나누나
#   terraform 은 VPC·EKS·IAM·RDS·SQS 를 다 만들어야 해서 사실상 관리자 권한이 필요하다.
#   그 하나짜리 역할로 plan 까지 돌리면, **PR 이 열릴 때마다 관리자 자격증명이 CI 에서 돈다.**
#   terraform plan 은 external data source 로 임의 코드를 실행할 수 있다 — 이 레포는 PUBLIC 이다.
#
#     plan  역할 : 읽기 전용. 인프라를 '바꾸거나 지울 수 없다'         → PR 마다 자동 실행
#     apply 역할 : 넓은 권한. GitHub environment 승인 뒤에만 쓸 수 있다 → 승인 후에만
#
# ⚠️ 정직하게 — plan 역할도 DB 비번에는 접근한다. 막을 수 없다.
#    tfstate 에 시크릿이 평문으로 들어가고(§3), plan 은 그 state 를 읽어야 하기 때문이다.
#    ReadOnlyAccess 가 secretsmanager:GetSecretValue 를 안 주지만(실측), state 를 읽는 이상
#    비번은 어차피 보인다. IAM 으로 막는 건 보여주기다.
#    **진짜 방어선은 '누가 이 워크플로를 돌릴 수 있느냐' 다** → 아래 신뢰정책의 sub 조건.
#    (그래도 역할을 나누는 값어치는 있다: plan 은 인프라를 '바꾸거나 지울 수' 없다.)

locals {
  tf_plan_role_name  = "${var.project_name}-${var.environment}-gha-tf-plan"
  tf_apply_role_name = "${var.project_name}-${var.environment}-gha-tf-apply"

  tfstate_bucket_arn = "arn:aws:s3:::${var.tfstate_bucket}"
}

# ── plan 역할 신뢰정책 ─────────────────────────────────────
# infra 레포의 PR 과 dev 브랜치 push 에서만 맡을 수 있다.
# ※ 포크가 연 PR 에는 GitHub 이 OIDC 토큰(id-token)을 주지 않는다 → 남이 이 역할을 못 맡는다.
data "aws_iam_policy_document" "tf_plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # ⚠️ sub 를 좁히지 않으면 '이 org 의 아무 레포나' 이 역할을 맡는다.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.infra_repo}:pull_request",
        "repo:${var.github_org}/${var.infra_repo}:ref:refs/heads/dev",
      ]
    }
  }
}

resource "aws_iam_role" "tf_plan" {
  name               = local.tf_plan_role_name
  description        = "GitHub Actions - terraform plan 전용(읽기). infra 레포의 PR·dev push 만 assume 가능."
  assume_role_policy = data.aws_iam_policy_document.tf_plan_assume.json
  tags               = merge(var.tags, { Name = local.tf_plan_role_name })
}

# 읽기 전체 — terraform 은 모든 리소스의 현재 상태를 Describe/Get/List 로 훑어야 plan 을 만든다.
resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess 만으로는 plan 이 죽는 두 곳을 메운다.
data "aws_iam_policy_document" "tf_plan_extra" {
  # ① tfstate 잠금 — plan 도 state 를 잠근다(use_lockfile=true → S3 에 <key>.tflock 을 쓰고 지운다).
  #    ReadOnlyAccess 는 PutObject·DeleteObject 를 안 준다 → plan 이 잠금을 못 걸어 죽는다.
  #
  # ⭐ 대상을 '잠금 파일 하나' 로 못 박는다. 버킷 전체(/*)에 쓰기를 주면 안 된다.
  #    plan 역할이 terraform.tfstate 자체를 덮어쓰거나 지울 수 있게 되기 때문이다.
  #    state 를 조작하면 인프라를 직접 바꾸지 않고도 '다음 apply 가 리소스를 파괴하게' 만들 수 있다
  #    (terraform 이 실재하는 리소스를 모른다고 착각하거나, 지워야 할 것으로 보게 된다).
  #    → "plan 은 인프라를 바꾸거나 지울 수 없다" 는 이 설계의 핵심 주장이 거기서 무너진다.
  #
  #    읽기는 여기서 줄 필요가 없다 — ReadOnlyAccess 가 s3:GetObject·ListBucket 을 이미 준다.
  #    plan 은 state 를 '읽기만' 한다. 쓰지 않는다(state 를 갱신하는 건 apply 다).
  statement {
    sid    = "TfStateLockFileOnly"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.tfstate_bucket_arn}/${var.tfstate_key}.tflock"]
  }

  # ② aws_secretsmanager_secret_version 을 refresh 하려면 값을 읽어야 한다.
  #    ReadOnlyAccess 에는 GetSecretValue 가 없다(실측: Describe*·List* 만).
  #    없으면 plan 이 AccessDenied 로 죽는다.
  #    ⚠️ 이걸 준다고 새로 위험해지는 건 아니다 — 어차피 tfstate 에 비번이 평문으로 있고
  #       plan 은 그 state 를 읽는다. 다만 '우리 시크릿 하나' 로 좁혀 둔다.
  statement {
    sid       = "ReadOwnSecretForRefresh"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.environment}-*"]
  }
}

resource "aws_iam_role_policy" "tf_plan_extra" {
  name   = "tf-plan-extra"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_plan_extra.json
}

# ── apply 역할 신뢰정책 ────────────────────────────────────
# ⭐ 여기가 이 설계의 핵심이다.
#    sub 를 'environment:<이름>' 으로 좁히면, 그 GitHub environment 에서 도는 job 만
#    이 sub 를 가진 토큰을 받는다. environment 에 **필수 리뷰어**를 걸어 두면
#    승인 전에는 그 job 이 시작조차 안 되고 → 토큰도 안 나오고 → **AWS 가 assume 을 거부**한다.
#
#    즉 '수동 승인 게이트'가 GitHub UI 설정이 아니라 **AWS 레벨에서 강제**된다.
#    누가 워크플로 파일을 고쳐 승인을 건너뛰려 해도, environment 를 안 거치면 sub 가 달라져
#    이 역할을 못 맡는다.
#
# ⚠️ 배포팀/팀장 할 일: GitHub 레포 Settings → Environments → `infra-apply` 생성 →
#    Required reviewers 지정. 이 환경이 없으면 apply job 이 아예 못 돈다.
data "aws_iam_policy_document" "tf_apply_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # StringEquals 다(StringLike 가 아니다) — 와일드카드를 허용하지 않는다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.infra_repo}:environment:${var.apply_environment}"]
    }
  }
}

resource "aws_iam_role" "tf_apply" {
  name               = local.tf_apply_role_name
  description        = "GitHub Actions - terraform apply. '${var.apply_environment}' environment 승인 후에만 assume 가능."
  assume_role_policy = data.aws_iam_policy_document.tf_apply_assume.json
  tags               = merge(var.tags, { Name = local.tf_apply_role_name })
}

# ── apply 권한 ─────────────────────────────────────────────
# terraform 이 만드는 것 전부에 권한이 필요하다. Resource 를 좁힐 수 없다 —
# 아직 존재하지 않는 리소스의 ARN 을 미리 알 수 없기 때문이다.
# AdministratorAccess 를 붙이지 않고 '쓰는 서비스만' 명시한다. 두 가지가 남는다:
#   ① 무엇을 쓰는지가 코드에 드러난다(나중에 좁히기 쉽다)
#   ② 조직·결제·계정 설정에는 손을 못 댄다
data "aws_iam_policy_document" "tf_apply" {
  statement {
    sid    = "TerraformManagedServices"
    effect = "Allow"
    actions = [
      "ec2:*",                     # VPC·서브넷·NAT·SG·엔드포인트·런치템플릿
      "eks:*",                     # 클러스터·노드그룹·access entry·애드온
      "iam:*",                     # IRSA 역할 8종·OIDC provider·정책
      "rds:*",                     # RDS·서브넷그룹
      "s3:*",                      # 모델 버킷·tfstate
      "sqs:*",                     # 콜 큐·Karpenter 중단 큐
      "dynamodb:*",                # 오답노트
      "ecr:*",                     # 이미지 레포 6종
      "secretsmanager:*",          # DB 자격증명
      "ssm:*",                     # Parameter Store
      "events:*",                  # EventBridge 규칙(Karpenter 중단)
      "logs:*",                    # CloudWatch 로그그룹
      "kms:*",                     # 암호화 키 참조
      "elasticloadbalancing:*",    # ALB(컨트롤러가 만들지만 terraform 이 조회)
      "autoscaling:*",             # 노드그룹 ASG
      "application-autoscaling:*", # 스케일링 정책
      "cloudwatch:*",              # 알람·지표
      "tag:*",                     # 태그 조회
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  # ⚠️ IAM '유저' 관련은 명시적으로 막는다.
  #    terraform 은 IAM 유저를 만들지 않는다(역할만 만든다). 그런데 iam:* 가 열려 있으면
  #    이 역할을 탈취한 사람이 **유저 + 액세스 키**를 만들어 CI 밖에서도 계속 쓸 수 있다.
  #    OIDC 의 장점(단기 토큰)이 통째로 무력해진다. 쓸 일이 없으니 닫는다.
  statement {
    sid    = "DenyIamUserPersistence"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:AddUserToGroup",
    ]
    resources = ["*"]
  }

  # 조직·결제·계정 설정은 terraform 소관이 아니다. 사고 반경을 줄인다.
  statement {
    sid    = "DenyOrgAndBilling"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
      "aws-portal:*",
      "billing:*",
      "budgets:*",
      "ce:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tf_apply" {
  name   = "tf-apply"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply.json
}
