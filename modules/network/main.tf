# network 모듈 - main.tf
# 모든 워크로드가 올라갈 VPC(울타리 친 단독주택 단지)와 그 안의 도로(서브넷·라우팅).
#   - public 서브넷 : 인터넷 향 LB·NAT 가 사는 곳(대문 쪽)
#   - private 서브넷: EKS 노드·파드가 사는 곳(집 안쪽) → 밖으로 나갈 땐 NAT 경유
#
# 이름은 하드코딩 대신 name_prefix 로 파생해 단일 진실원천(규약서 §2)을 지킨다.
locals {
  name_prefix = "${var.project_name}-${var.environment}" # hailcast-dev
  # 서브넷 이름에는 AZ 전체가 아니라 접미사(2a·2c)만 쓴다 — 규약서 §5-1 (hailcast-dev-subnet-public-2a)
  az_suffix = [for az in var.availability_zones : substr(az, length(az) - 2, 2)]
}

############################################
# VPC
############################################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

############################################
# Internet Gateway
############################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

############################################
# Public Subnets
############################################
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-subnet-public-${local.az_suffix[count.index]}"
    Type = "public"
    # AWS LB Controller 가 '인터넷 향 ALB' 를 놓을 퍼블릭 서브넷을 이 태그로 자동 발견한다.
    # (private 의 internal-elb 와 짝. 빠지면 ALB 생성이 실패한다 — 규약서 §6-1)
    "kubernetes.io/role/elb" = "1"
  }
}

############################################
# Private Subnets
############################################
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name_prefix}-subnet-private-${local.az_suffix[count.index]}"
    Type = "private"
    # 내부 향 LB 자동 발견용.
    "kubernetes.io/role/internal-elb" = "1"
    # Karpenter 가 노드를 띄울 서브넷을 이 값으로 찾는다. manifests 의 Karpenter 설정도 같은 값을 참조해야 함.
    "karpenter.sh/discovery" = local.name_prefix
  }
}

############################################
# Public Route Table
############################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-public"
  }
}

############################################
# Private Route Table (단일 NAT 확정 → RT 도 1개면 충분)
############################################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-private"
  }
}

############################################
# Route Table Association
############################################
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 모든 private 서브넷이 단일 private RT 를 공유한다.
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
