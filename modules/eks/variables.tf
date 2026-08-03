# eks 모듈 - variables.tf
variable "project_name" {
  description = "프로젝트 접두사 (예: hailcast)."
  type        = string
  default     = "hailcast"
}

variable "environment" {
  description = "환경 구분자 (예: dev)."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "공통 태그 (비용 배분·OpenCost 판별용)."
  type        = map(string)
  default     = {}
}

# ── 클러스터 배선용 입력 (envs/dev 가 network 출력을 스레딩) ──

variable "private_subnet_ids" {
  description = "컨트롤플레인 ENI·노드가 들어갈 프라이빗 서브넷 ID 목록(≥2 AZ). network 출력."
  type        = list(string)
}

variable "cluster_version" {
  description = "EKS 버전. ⚠️ apply 전 AWS 표준지원 버전 재확인(규약서 §5-3)."
  type        = string
  default     = "1.35"
}

variable "public_access_cidrs" {
  description = "퍼블릭 엔드포인트 허용 대역. 데모 기본 0.0.0.0/0(=네트워크 도달만 허용, 조작은 IAM+RBAC 필요). 운영 시 내 IP/CIDR 로 조인다."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── 노드그룹(M2) 입력 ──

variable "vpc_id" {
  description = "노드 SG 를 붙일 VPC ID (network 출력)."
  type        = string
}

variable "node_instance_types" {
  description = "system 노드그룹 인스턴스 타입. 플랫폼(ArgoCD·Prometheus) 수용 위해 t3.large."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_min_size" {
  description = "system 노드그룹 최소 노드 수(HA 위해 2)."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "system 노드그룹 희망 노드 수."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "system 노드그룹 최대 노드 수(롤링·일시 여유 상한)."
  type        = number
  default     = 3
}

# ── IRSA(M3) 앱 5종이 지목할 데이터 리소스 ARN ────────────────────────────
# 이 모듈은 S3·SQS·DynamoDB 를 '만들지' 않고 ARN 만 '받아쓴다'. storage·data 모듈의
# output 을 envs/dev 가 여기로 스레딩한다(§4 — vpc_id 를 network 에서 받는 것과 같은 패턴).
# 자식 모듈은 형제 모듈(module.storage)을 볼 수 없으므로, 값 전달은 루트를 거치는 이 방법뿐이다.

variable "enable_app_irsa" {
  description = <<-EOT
    앱 IRSA 8종(predict·call-api·worker·weather-cron·keda·karpenter·simulator·eso) 생성 스위치.
    상시 2종(lbctrl·monitoring)과 합쳐 IRSA 는 총 10종이다(§5-3).
    아래 ARN 4종(S3 · 콜 큐 · Karpenter 중단 큐 · RDS 시크릿)이 배선된 뒤 envs/dev 에서 true 로 켠다.
    오답노트 DynamoDB 는 전제조건이 아니다 — 아래 validation 주석 참조.

    ※ weather-cron 은 2026-07-14 신설이다. 날씨 CSV 는 파일 아티팩트라 RDS 컷오버 뒤에도
      S3 를 지나간다(규약서 §8-3). 이 역할이 없으면 CSV 가 안 올라가고
      predict 가 못 읽어 예측이 통째로 안 된다.

    ※ simulator 는 K8s 에 s3 백엔드로 뜬다(팀 결정). JSON_STORE_BACKEND=s3 라 2초마다
      simulator/status.json 을 S3 에 쓴다. irsa-simulator 가 simulator/ 쓰기를 갖고,
      predict 는 그 파일을 읽으려 simulator/ 읽기를 갖는다(§5-3).

    ※ forecast 역할은 없다(§5-3 · 2026-07-13 폐기). 결정 1 = predict 내장이라
      예측을 S3 에 쓰는 일을 predict 안의 스케줄러가 한다 → forecast-sa 를 달 파드가 없다.

    ⚠️ ARN 이 null 인지로 자동 판단하지 않는 이유: storage·data 의 output 은 리소스가 아직
       없는 첫 plan 에서 '미상(unknown)' 이다. 미상값에 `!= null` 을 걸면 결과도 미상이 되고,
       그걸 for_each/count 조건에 쓰면 `Invalid for_each argument` 로 plan 자체가 죽는다.
       그래서 판단 근거를 '값'이 아니라 plan 시점에 확정된 '리터럴 불리언'으로 둔다.
  EOT
  type        = bool
  default     = false

  # 플래그만 켜고 ARN 을 빠뜨리면 templatefile 이 "null 보간" 같은 알기 어려운 에러를 뱉는다.
  # 여기서 미리 사람이 읽을 수 있는 말로 세워둔다. (교차 변수 참조는 Terraform 1.9+ 기능,
  # 루트가 required_version >= 1.11 이라 안전하다.)
  #
  # 강제하는 건 5종이다. prediction_log_table_arn(오답노트)은 뺐다.
  #    다섯 다 '없으면 앱이 실제로 죽는' 권한이다 — S3 없으면 모델 로드 실패, 콜 큐 없으면
  #    call-api·worker 가 멈추고, 중단 큐 없으면 Karpenter 가 Spot 경고를 못 받고,
  #    RDS 시크릿 없으면 eso 가 비번을, 엔드포인트 파라미터 없으면 DB_HOST 를 못 읽어
  #    DB 접속이 통째로 막힌다.
  #    오답노트는 다르다. 규약서 §5-3 이 인정하듯 '쓰는 앱 코드가 아직 0건'이라 권한이 없어도
  #    아무도 죽지 않는다. 그런데 이걸 함께 강제하면, 아무도 안 쓰는 테이블 하나가
  #    'karpenter' 역할까지 인질로 잡는다(같은 스위치에 묶여 있으므로) → 노드 공급이 막힌다.
  #    그래서 오답노트 권한은 irsa.tf 에서 dynamic 으로 두어 'ARN 이 오면 붙고 없으면 건너뛴다'.
  validation {
    condition = !var.enable_app_irsa || alltrue([
      var.model_bucket_arn != null,
      var.sqs_call_queue_arn != null,
      var.karpenter_interruption_queue_arn != null,
      var.rds_master_secret_arn != null,
      var.rds_endpoint_param_arn != null,
    ])
    error_message = "enable_app_irsa = true 로 켜려면 ARN 5종(model_bucket_arn · sqs_call_queue_arn · karpenter_interruption_queue_arn · rds_master_secret_arn · rds_endpoint_param_arn)을 주입해야 합니다. (prediction_log_table_arn 은 선택 — 주입하면 predict 에 오답노트 쓰기 권한이 붙습니다.)"
  }
}

variable "model_bucket_arn" {
  description = <<-EOT
    앱의 유일한 상태 저장소인 S3 버킷 ARN (storage output).
    이름은 '모델' 버킷이지만 앱이 DB 를 빼면서(app common/core/store.py:2) 콜 기록·트래픽 집계·
    스케일 이력·대시보드·날씨 CSV 까지 전부 이 버킷 하나를 지나간다.
    IRSA 4종(predict·call-api·worker·weather-cron)이 프리픽스별로 잘라 쓴다 — 표는 irsa.tf 참조.
  EOT
  type        = string
  default     = null
}

variable "sqs_call_queue_arn" {
  description = "콜 큐 ARN (data output `sqs_queue_arn`, §7). call-api 송신 · worker 수신/삭제 · keda/predict 는 길이 조회만."
  type        = string
  default     = null
}

variable "prediction_log_table_arn" {
  description = <<-EOT
    예측 오답노트 DynamoDB 테이블 ARN (data output). predict 가 예측 실패를 기록(쓰기 전용).

    ⭐ 선택 항목이다. null 이어도 enable_app_irsa 를 켤 수 있고, 그때는 오답노트 쓰기
       statement 자체가 만들어지지 않는다(irsa.tf 의 dynamic). 앱에 이 테이블을 쓰는 코드가
       아직 없기 때문이다(§5-3). data 모듈이 테이블을 만들면 루트에서 이 값을 넘기기만 하면
       된다 — eks 모듈 코드는 고칠 게 없다.
  EOT
  type        = string
  default     = null
}

variable "rds_master_secret_arn" {
  description = "RDS 자동생성 마스터 비번 시크릿 ARN (data output). eso IRSA 가 GetSecretValue 로 읽어 K8s Secret 으로 동기화한다(§5-4)."
  type        = string
  default     = null
}

variable "rds_endpoint_param_arn" {
  description = "RDS 엔드포인트 파라미터 ARN (data output). eso IRSA 가 ssm:GetParameter 로 읽어 같은 K8s Secret 에 DB_HOST 로 병합한다(§5-4 계약 표)."
  type        = string
  default     = null
}

variable "karpenter_interruption_queue_arn" {
  description = "Karpenter 중단 큐 ARN (data output). Spot 회수 2분 경고를 수신한다 — 없으면 중단 처리가 통째로 꺼진다(§5-4)."
  type        = string
  default     = null
}

# ── 클러스터 출입 명단 (access.tf) ────────────────────────────────────────
# ⚠️ ARN 에는 계정 ID 가 들어간다. 이 레포는 퍼블릭이다 → 실제 값은 terraform.tfvars(gitignore)에만.

variable "cluster_admin_principal_arns" {
  description = <<-EOT
    클러스터 전권(cluster-admin)을 줄 IAM principal ARN 목록.
    애드온(ArgoCD·KEDA·Karpenter·ALB Controller)을 클러스터 전역에 설치해야 하는 사람.

    ⚠️ apply 를 실행하는 principal 은 넣지 마라 — bootstrap 으로 자동 등재되므로
       중복 엔트리가 되어 apply 가 실패한다.
  EOT
  type        = list(string)
  default     = []
}

variable "cluster_editor_principal_arns" {
  description = <<-EOT
    앱 네임스페이스 안에서만 편집 권한(AmazonEKSEditPolicy)을 줄 IAM principal ARN 목록.
    파드 로그·재시작·exec 은 되지만 클러스터 전역 리소스(노드·CRD·다른 네임스페이스)는 못 건드린다.
    나중에 전권이 필요해지면 tfvars 에서 admin 목록으로 옮긴다(코드는 안 고친다).
  EOT
  type        = list(string)
  default     = []
}

variable "editor_namespaces" {
  description = "editor 권한이 미치는 네임스페이스(§8 앱 네임스페이스)."
  type        = list(string)
  default     = ["hailcast"]
}
