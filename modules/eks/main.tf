# eks 모듈 - main.tf
# 지금 단계: 클러스터 OIDC 와 무관한 IAM 역할만 선(先) 생성한다.
#   - 클러스터 컨트롤플레인 역할 · 노드그룹 역할 (둘 다 클러스터보다 먼저 존재해야 함)
#   - IRSA 10종(base 2 + 앱 8 · 규약서 §5-3)은 클러스터·OIDC 가 생긴 뒤 이 모듈(irsa.tf)에 이어서 추가한다.
locals {
  name_prefix = "${var.project_name}-${var.environment}" # hailcast-dev
}
