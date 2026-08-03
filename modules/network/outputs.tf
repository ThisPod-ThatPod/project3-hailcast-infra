# network 모듈 - outputs.tf
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = aws_subnet.private[*].id
}

output "vpc_cidr" {
  description = "VPC CIDR 블록"
  value       = aws_vpc.this.cidr_block
}

# 게이트웨이 엔드포인트 추가 연결이나 data 모듈에서 참조할 수 있게 노출.
output "private_route_table_id" {
  description = "단일 프라이빗 라우트 테이블 ID."
  value       = aws_route_table.private.id
}

# RDS 서브넷 그룹·EKS 등이 '어느 AZ 를 쓰는지' 알아야 할 때 참조하는 단일 소스.
output "availability_zones" {
  description = "이 VPC 가 사용하는 가용 영역 목록."
  value       = var.availability_zones
}