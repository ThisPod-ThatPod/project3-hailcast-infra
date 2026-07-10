# cicd 모듈 - outputs.tf
output "github_actions_role_arn" {
  description = "GitHub Actions 워크플로가 assume 할 역할 ARN. aws-actions/configure-aws-credentials 의 role-to-assume 에 넣는다."
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN(생성했거나 기존 참조 중인 것)."
  value       = local.github_oidc_arn
}
