# cicd 모듈 - main.tf
# GitHub Actions 가 AWS 를 '장기 비밀키 없이' 잠깐 빌려 쓰게 하는 OIDC 연동.
#   흐름: GitHub 이 발급한 단기 토큰 → AWS 가 신뢰(OIDC provider) → 지정 레포에만 역할 부여.
#   효과: 액세스키를 GitHub Secrets 에 저장할 필요가 없어져 키 유출 위험이 사라진다.
#
# ⚠️ GitHub OIDC provider 는 'AWS 계정당 1개'다. 이미 있으면 apply 가 EntityAlreadyExists 로 실패한다.
#    → create_oidc_provider=false 로 두면 아래 data 소스로 기존 것을 참조한다(재-apply 안전).
#      (이미 만든 뒤 상태에 흡수만 하려면 `terraform import` 도 가능하다.)

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# OIDC 엔드포인트 인증서 지문을 동적으로 계산 → 지문 하드코딩/만료 걱정 없음.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# 새로 만드는 경우(계정에 아직 없음).
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "github-actions-oidc" })
}

# 이미 있는 경우 기존 provider 를 조회.
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

# 생성/참조 중 실제 존재하는 ARN 하나를 고정 참조점으로 통일한다.
locals {
  github_oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ── 신뢰정책: 우리 app 레포의 워크플로만 이 역할을 맡을 수 있다 ──
data "aws_iam_policy_document" "gha_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    # aud 는 정확히 일치해야 함(고정 값).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # sub 를 특정 레포로 좁힌다. 다른 레포/포크는 이 역할을 못 맡는다.
    #
    # ⭐ 레포뿐 아니라 '브랜치' 까지 좁힌다. 옛 값은 `repo:<org>/<repo>:*` 였는데,
    #    그 와일드카드는 PR 에서 도는 job(sub = ...:pull_request)까지 허용한다
    #    → app 레포에 브랜치를 푸시할 수 있는 사람이 임의 이미지를 ECR 에 올릴 수 있고,
    #      ArgoCD 는 그 태그를 그대로 배포한다.
    #    앱 CI 는 main push 와 workflow_dispatch 로만 돈다(app .github/workflows/build.yml:5-7)
    #    → 아래 두 ref 로 충분하다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/dev",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  # 이름은 규약서 §5-6의 단일 진실원천을 그대로 따른다: hailcast-dev-gha-ecr
  name               = "${var.project_name}-${var.environment}-gha-ecr"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
  tags               = merge(var.tags, { Name = "${var.project_name}-${var.environment}-gha-ecr" })
}

# ── 권한: hailcast-dev-* ECR 레포에 이미지 push 만 (최소권한) ──
data "aws_iam_policy_document" "ecr_push" {
  # 인증 토큰 발급은 리소스 지정이 불가능한 계정 단위 액션이라 * 가 불가피하다.
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  # 실제 push/read 는 우리 프로젝트 ECR 레포로만 제한한다.
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-${var.environment}-*",
    ]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
