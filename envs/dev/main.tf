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
# 모듈 참조는 data ↔ eks 양방향이지만(data 의 큐·시크릿 ARN → eks IRSA 정책 · eks 노드 SG → data ingress 규칙)
# 서로 다른 리소스 체인이라 리소스 단위 그래프에는 순환이 없다.
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

  # ── 클러스터 출입 명단 (access.tf) — 사람이 kubectl 을 쓰려면 여기 올라야 한다 ──
  # 값은 terraform.tfvars(gitignore)에 있다 — ARN 에 계정 ID 가 들어가고 이 레포는 퍼블릭이다.
  # admin  = 클러스터 전권 (애드온 설치)  ·  editor = hailcast 네임스페이스 편집만 (디버깅)
  #
  # ⚠️ 첫 apply 를 사람이 로컬에서 하므로 그 사람은 bootstrap 으로 자동 등재된다.
  #    목록에 또 넣으면 중복 엔트리가 되어 apply 가 실패한다.
  cluster_admin_principal_arns  = var.cluster_admin_principal_arns
  cluster_editor_principal_arns = var.cluster_editor_principal_arns

  # ── IRSA 앱 6종 배선 (predict · call-api · worker · weather-cron · keda · karpenter) ──
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

  # 오답노트 DynamoDB(predict 쓰기) · RDS 자동생성 시크릿(eso 읽기) 배선.
  prediction_log_table_arn = module.data.prediction_log_table_arn
  rds_master_secret_arn    = module.data.rds_master_secret_arn
  rds_endpoint_param_arn   = module.data.rds_endpoint_param_arn
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

# ── Y7 엣지 — Route53 + CloudFront ──────────────────────────
# 트랙 맨 끝: ALB(배포팀 Ingress)가 떠야 오리진을 연결할 수 있다.
#   enable_edge = false  → 리소스 0개 (기본. 다른 팀 apply 를 막지 않는다)
#   enable_edge = true   → ACM 인증서 2종 발급 (ALB 없어도 됨)
#   + alb_dns_name 채움  → CloudFront·레코드까지 생성
module "edge" {
  source = "../../modules/edge"
  count  = var.enable_edge ? 1 : 0

  # 형제 모듈끼리는 서로를 못 본다. provider 도 루트가 넘겨준다.
  providers = {
    aws          = aws
    aws.virginia = aws.virginia
  }

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
  alb_dns_name = var.alb_dns_name
}