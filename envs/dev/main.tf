# envs/dev - main.tf
# 이 환경을 구성하는 모듈들을 '조립'하는 곳. 각 모듈은 로컬 경로로 호출한다.
# 공통 비용 태그는 providers.tf 의 default_tags 가 전 리소스에 자동 부착하므로
# 모듈에 tags 를 따로 넘기지 않는다(이중 선언 방지). 모듈은 리소스별 Name 만 붙인다.

# ── 네트워크: VPC·서브넷·NAT·게이트웨이 엔드포인트 ──
module "network" {
  source = "../../modules/network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── 데이터: RDS(PostgreSQL) + 자격증명(Secrets Manager) + DB 주소(Parameter Store) ──
# network 출력을 스레딩해 RDS 를 프라이빗 서브넷에 배치한다. AZ 는 목록 첫째(Single-AZ 데모).
module "data" {
  source = "../../modules/data"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  rds_availability_zone = var.availability_zones[0]
}

# ── EKS 선행 IAM: 컨트롤플레인·노드그룹 역할 (클러스터 본체 붙기 전에 미리 준비) ──
module "eks" {
  source = "../../modules/eks"

  project_name = var.project_name
  environment  = var.environment
}

# ── 스토리지: app 이미지용 ECR 레포(call-api·predict·weather-cron·worker) + S3 ──
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
}

# ── CI/CD: GitHub Actions OIDC + ECR push 역할 ──
module "cicd" {
  source = "../../modules/cicd"

  project_name = var.project_name
  environment  = var.environment
}
