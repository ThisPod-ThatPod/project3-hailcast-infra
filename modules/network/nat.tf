resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags = {
    Name = "hailcast-dev-eip-nat"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  # public-2a (index 0)
  subnet_id = aws_subnet.public[0].id

  tags = {
    Name = "hailcast-dev-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

