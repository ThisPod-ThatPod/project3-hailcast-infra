# storage 모듈 - main.tf
# app 레포가 빌드한 컨테이너 이미지를 담는 사설 창고(ECR).
#   흐름: GitHub Actions(cicd 역할) → docker push → 이 레포 → EKS 노드가 pull.
#   cicd 역할은 hailcast-dev-* 레포에만 push 권한이 있으므로, 레포명 접두사가 그 패턴과 맞아야 한다.
#
# for_each 는 정적 리스트(var.repositories)라 apply 안전. 레포를 늘리려면 변수 목록에 이름만 추가.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name = "${var.project_name}-${var.environment}-${each.value}"

  # dev 는 같은 태그(latest 등) 덮어쓰기가 잦아 MUTABLE. 운영 승격 시 IMMUTABLE 로 조인다.
  image_tag_mutability = "MUTABLE"

  # push 시 취약점 자동 스캔(무료 basic). 이미지에 알려진 CVE 가 있으면 콘솔/이벤트로 통지.
  image_scanning_configuration {
    scan_on_push = true
  }

  # dev 편의: 이미지가 남아 있어도 destroy 가 막히지 않게 한다. 운영에서는 false 로 둔다.
  force_delete = true

  tags = merge(var.tags, { Name = "${var.project_name}-${var.environment}-${each.value}" })
}

# 레포마다 수명주기 정책: 오래된/태그 없는 이미지를 자동 정리해 스토리지 비용을 억제한다.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "태그 없는(dangling) 이미지는 14일 후 만료"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "최신 ${var.image_keep_count}개 태그 이미지만 보관"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_keep_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
