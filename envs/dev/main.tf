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
# eks 노드 SG 를 받아 RDS 5432 인바운드를 그 SG 에서 온 것만 허용한다(§5-5).
# 의존 방향은 network → eks → data 한 방향뿐이라 순환이 없다(eks 는 data 를 참조하지 않는다).
module "data" {
  source = "../../modules/data"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  rds_availability_zone  = var.availability_zones[0]
  node_security_group_id = module.eks.node_security_group_id
}

# ── EKS: 컨트롤플레인 본체 + OIDC(IRSA 전제) + 선행 IAM 역할 ──
# network 의 private 서브넷을 스레딩해 컨트롤플레인 ENI·노드를 배치한다.
# cluster_version(1.35)·public_access_cidrs(0.0.0.0/0)는 모듈 기본값 사용.
# 엔드포인트를 조이려면 public_access_cidrs = ["<내IP>/32"] 로 오버라이드.
module "eks" {
  source = "../../modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  # 노드그룹 규모(2× t3.large·min2/max3)는 모듈 기본값 사용.

  # ── IRSA 앱 5종 배선 (predict · call-api · worker · keda · karpenter) ──
  # 자식 모듈은 형제 모듈을 볼 수 없다(module.storage 를 modules/eks 안에서 못 쓴다).
  # 그래서 '루트가 output 을 읽어 다음 모듈의 변수로 넘기는' 이 중계가 유일한 방법이다(§4).
  #
  # ⚠️ enable_app_irsa 는 ARN 이 null 인지로 자동 판단하지 않는다.
  #    storage·data 의 output 은 첫 plan 에서 '미상(unknown)' 이라, 미상값에 조건을 걸어
  #    for_each 에 쓰면 `Invalid for_each argument` 로 plan 자체가 죽는다.
  #    판단 근거를 plan 시점에 확정되는 '리터럴 불리언' 으로 둔 이유다.
  enable_app_irsa                  = true
  model_bucket_arn                 = module.storage.model_bucket_arn # storage → eks
  sqs_call_queue_arn               = module.data.sqs_queue_arn       # data    → eks
  karpenter_interruption_queue_arn = module.data.karpenter_queue_arn # data    → eks

  # 오답노트 DynamoDB 는 전제조건이 아니다(앱 미구현 · 스키마 미확정).
  # null 이면 IRSA predict 의 DynamoDB 문(statement)만 빠지고 나머지는 그대로 만들어진다
  # (modules/eks/irsa.tf 의 dynamic 블록). 테이블이 생기면 이 줄만 이어 붙인다.
  # prediction_log_table_arn = module.data.prediction_log_table_arn
}

# ── 스토리지: app 이미지용 ECR 레포(call-api·predict·weather-cron·worker) + S3 ──
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
}

# ── CI/CD: GitHub Actions OIDC + 역할 3종 ──
#   gha-ecr        : app 레포 → ECR 이미지 push (최소권한)
#   gha-tf-plan    : infra 레포 → terraform plan (읽기 전용). PR 마다 자동
#   gha-tf-apply   : infra 레포 → terraform apply (넓은 권한). environment 승인 후에만
#
# ⚠️ plan 과 apply 를 한 역할로 합치면, PR 이 열릴 때마다 관리자 자격증명이 CI 에서 돈다.
#    terraform plan 은 임의 코드를 실행할 수 있고 이 레포는 PUBLIC 이다. 그래서 나눈다.
module "cicd" {
  source = "../../modules/cicd"

  project_name = var.project_name
  environment  = var.environment

  # plan 역할이 tfstate 잠금 파일(<key>.tflock)을 쓰고 지울 수 있어야 한다(use_lockfile=true).
  # ⚠️ 둘 다 backend.tf 와 반드시 같은 값이다. 어긋나면 plan 이 잠금을 못 걸어 죽는다.
  #    (backend 블록은 변수를 못 받아서 값을 두 곳에 적을 수밖에 없다.)
  tfstate_bucket = "hailcast-dev-tfstate-7dde"
  tfstate_key    = "dev/terraform.tfstate"
}
