# network 모듈 - nat.tf
# private 서브넷이 밖(인터넷)으로 '나가기만' 할 때 쓰는 단방향 문(NAT).
# 우리는 NAT 를 항상 켜므로 토글 없이 무조건 1개 생성한다(비용상 단일 NAT = 의도된 선택).
#   ⚠️ 단일 NAT 는 그 AZ 장애 시 private 전체 egress 가 끊기는 SPOF 임을 인지하고 쓴다.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-eip-nat"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # 첫 public 서브넷에 배치

  tags = {
    Name = "${local.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}
