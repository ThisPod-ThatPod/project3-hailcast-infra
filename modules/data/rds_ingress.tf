# data 모듈 - rds_ingress.tf  (M4)
#
# 규약서 §5-5: RDS SG 의 5432 인바운드는 '노드 SG 에서 온 것만' 허용한다.
# main.tf 는 노드 SG 가 아직 없던 시점이라 RDS SG 를 zero-inbound 로 만들어 두었고,
# 노드 SG(M2, eks 모듈)가 생긴 지금 그 구멍을 여기서 연다.
#
# 왜 CIDR 이 아니라 'SG 참조'인가:
#   노드는 Karpenter 가 수시로 만들고 없앤다 → 사설 IP 가 계속 바뀐다.
#   CIDR 로 열면 서브넷 전체(10.0.32.0/20 등)를 열게 되어 그 안의 아무 리소스나 DB 에 닿는다.
#   SG 를 지목하면 'IP 가 무엇이든, 노드 SG 를 달고 있는 것만' 통과한다(실무 정석).
#
# 왜 별도 파일인가:
#   ① main.tf 의 egress 와 같이 '독립 rule 리소스'로만 관리한다(인라인 블록과 섞으면
#      Terraform 이 매 apply 마다 규칙을 지웠다 넣었다 하며 충돌 — AWS provider 공식 경고).
#   ② data 모듈은 둘이 나눠 작업하므로(유현상: sqs.tf·dynamodb.tf) 파일 단위로 충돌을 피한다.

resource "aws_vpc_security_group_ingress_rule" "rds_from_node" {
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL 5432 from EKS node SG only"

  referenced_security_group_id = var.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
