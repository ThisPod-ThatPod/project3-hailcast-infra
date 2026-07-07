# project3-hailcast-infra

> **hailcast** — AI 수요 예측 기반 오토스케일링 & FinOps 클라우드 인프라
> 날씨·시간 패턴으로 택시 호출 수요를 미리 예측해, 트래픽이 몰리기 **전에** 파드를 선제 확장하고 한산해지면 회수하는 예측형 자율 운영 인프라.
>
> Org: `ThisPod-ThatPod` · 리전: `ap-northeast-2`(서울) · 담당: 이미선, 유현상

---

## 1. 프로젝트 한눈에

하나의 **닫힌 제어 루프**를 다섯 관점으로 구현한다.

```
관측(Prometheus) → 예측(LightGBM) → 실행(KEDA·Karpenter) → 검증(Grafana·OpenCost) → 재예측
```

- **선제 예측 스케일링** — 예측값을 KEDA가 읽어 트래픽 전 파드 확장, 노드 부족 시 Karpenter가 EC2 공급
- **반응형 안전망** — 예측이 빗나가도 HPA(CPU/큐 기준)가 즉시 받침
- **GitOps** — Terraform(IaC) + GitHub Actions(CI) + ArgoCD(CD)
- **FinOps** — OpenCost로 비용 계측, 예측형 vs 반응형 절감폭을 시뮬레이션 수치로 제시

> **정직성 선언:** 실서비스가 아니다. "실측 절감"이 아니라 설계·구현 + 시뮬레이션 기대효과로 제시한다.

---

## 2. 레포 구조 (3-레포)

레포는 **배포 방식이 다르면 나눈다**는 기준으로 셋으로 분리한다.

| 레포 | 배포 방식 | 담당 |
| --- | --- | --- |
| `project3-hailcast-infra` (이 레포) | `terraform apply` | 인프라 |
| `project3-hailcast-app` | `docker build → ECR push` | 앱·ML |
| `project3-hailcast-manifests` | ArgoCD가 pull(GitOps) | 통합 |

**이 레포 내부 폴더**

```
project3-hailcast-infra/
├── envs/dev/                  # 조립·상태 (backend.tf, main.tf, variables.tf, terraform.tfvars)
├── modules/
│   ├── network/               # VPC·서브넷·NAT·라우팅
│   ├── storage/               # S3·ECR
│   ├── eks/                    # 클러스터·OIDC·Karpenter·IRSA (OIDC 의존 → 한 몸)
│   └── data/                   # RDS·SQS·DynamoDB·Karpenter 중단 큐·Secrets·Parameter Store
├── docs/
│   └── 네이밍규약서.md        # 전체 네이밍 사전 (이름의 단일 진실원천)
└── .github/workflows/terraform.yml
```

---

## 3. 아키텍처 요약 (Multi-AZ 4계층)

VPC `10.0.0.0/16` · AZ `2a·2c` 기준.

| 계층 | 구성 |
| --- | --- |
| 엣지/진입 | (CloudFront) → **ALB**(Ingress) + ALB Controller |
| 컴퓨트 (EKS·Private) | 콜 API · 워커 · 예측 · CronJob 3종 · addons(KEDA·HPA·Karpenter·ArgoCD) |
| 데이터/관리형 | **S3**(모델·예측JSON) · ECR · SQS(콜 큐) · **RDS PostgreSQL(Single-AZ)** · DynamoDB(오답노트) · Secrets Manager |
| 접근/보안 | **SSM Session Manager**(Bastion 대체, zero-inbound) · IAM/IRSA 최소 권한 |

> **변경 이력:** ElastiCache(Redis)는 **제거**했다. 예측 결과는 Prometheus(시계열)와 DynamoDB로 충분히 커버되어, 상시 과금 캐시 계층이 불필요하다고 판단(FinOps).

---

## 4. 협업 규약 (GitHub)

### 4-1. 권한은 최소로 — 두 체계를 구분

| 체계 | 정하는 것 | 비유 |
| --- | --- | --- |
| Organization Role (Owner/Member) | 조직 전체 관리 |
| Repository Role (Read/Write/Admin) | 레포 하나에서 할 수 있는 일 |

### 4-2. main 브랜치 보호 (레포마다 동일)

`Settings → Branches → Add rule`, 패턴 `main`:

- ✅ Require a pull request before merging (main 직접 push 금지)
- ✅ Require approvals: **1** (동료 1명 승인)
- ✅ Require conversation resolution before merging
- ⏳ infra만 추후 approvals **2**로 상향 검토 (인프라는 사고 파급이 큼)

### 4-3. 커밋·브랜치 컨벤션

- 브랜치: `main(보호) ← dev(통합) ← feature/*(개인)`
- 커밋: `[카테고리]: 내용` — 카테고리 `FEAT` / `REFAC` / `FIX` / `CHORE`
- PR: `[카테고리#이슈번호] 제목`

### 4-4. CODEOWNERS (선택)

레포 루트 `.github/CODEOWNERS` — PR 시 담당자 자동 리뷰 지정:

```
# 이 레포 전체 변경은 인프라 담당 2명이 리뷰한다
*   @github핸들1 @github핸들2
```

---

## 5. 네이밍 규약 (요약)

> 이름은 곧 계약이다. 여기 정한 문자열을 앱·ML·배포팀이 코드에 그대로 참조한다.
> 아래는 **자주 쓰는 핵심만** 추린 것이다. **전체 사전은 [`docs/네이밍규약서.md`](./docs/네이밍규약서.md)에 있고, 이름의 원본(진실)은 그 규약서다.**

### 5-1. 이름 공식

```
<project_name>-<environment>-<리소스종류>[-<식별자>]
예) hailcast-dev-vpc · hailcast-dev-rds-postgres
```

| 대상 | 규칙 |
| --- | --- |
| Terraform 변수 | `snake_case` |
| AWS 리소스 | `kebab-case` (소문자+하이픈) |
| S3 버킷 | 소문자+하이픈, 밑줄 금지, **전역 유일**(랜덤 접미사) |
| 예측 지표(메트릭) | `snake_case` |

### 5-2. 뿌리 변수 3형제

| 변수 | 값 |
| --- | --- |
| `project_name` | `hailcast` |
| `environment` | `dev` (단일 환경) |
| `aws_region` | `ap-northeast-2` |

### 5-3. 대표 리소스 이름

| 리소스 | 이름 |
| --- | --- |
| VPC | `hailcast-dev-vpc` |
| EKS 클러스터 | `hailcast-dev-eks` |
| System 노드그룹 | `hailcast-dev-eks-system-ng` (앱 노드는 Karpenter가 공급) |
| S3(모델·예측) | `hailcast-dev-model-artifacts-<랜덤>` |
| SQS(콜 큐) | `hailcast-dev-call-queue` |
| RDS | `hailcast-dev-rds-postgres` |
| Karpenter 중단 큐 | `hailcast-dev-eks` (Spot 중단 처리, 큐명은 임의 지정값) |
| tfstate 버킷 | `hailcast-dev-tfstate-<랜덤>` (S3 자체 잠금 → DynamoDB 불필요) |

### 5-4. 태그

**자동 발견 태그(기능용):** `kubernetes.io/role/elb=1`(public) · `kubernetes.io/role/internal-elb=1`(private) · `karpenter.sh/discovery=hailcast-dev`(private) · `kubernetes.io/cluster/hailcast-dev-eks=shared`(private)

**공통 비용 태그(`default_tags`):** `Project=hailcast` · `Environment=dev` · `ManagedBy=terraform`

> 📖 **모듈별 전 리소스 이름 · IRSA 역할 · SG · output 계약 · 팀 전체 공유 계약**은 [`docs/네이밍규약서.md`](./docs/네이밍규약서.md) 참조.

---

## 6. 워크로드 & CronJob

### 6-1. 상시 파드

| 파드 | 역할 |
| --- | --- |
| `call-api` | 콜 접수 → SQS 적재(즉시 응답) |
| `worker` | SQS 소비·처리 (**KEDA 스케일 대상**) |
| `predict` | 예측 서비스 (필요 시 `/metrics` 노출) |

### 6-2. CronJob 3종

| CronJob | 하는 일 | 산출물 |
| --- | --- | --- |
| `weather-cron` | Open-Meteo 예보 수집 | 예측 입력 데이터 |
| `demand-forecast-cronjob` | 모델 로드(S3) → LightGBM 예측 → JSON 생성 → S3 업로드 | `s3://.../predictions/latest.json` |
| `keda-scaler-updater-cronjob` | 위 JSON 읽기 → 목표 파드 수 계산 → **ScaledObject 갱신(patch)** | KEDA cron 스케줄 |

**예측 → 스케일 흐름**

```
[demand-forecast-cronjob]
  모델 로드(S3) → 예측 계산 → JSON 생성 → S3 업로드
        │  s3://hailcast-dev-model-artifacts-.../predictions/latest.json
        ▼
[keda-scaler-updater-cronjob]
  JSON 읽기 → 시간대별 목표 파드 수 계산 → worker의 ScaledObject를 patch
        │
        ▼
[KEDA] cron 트리거로 worker 선제 확장 → [Karpenter] 노드 공급
```

> **설계 의도(개발팀):** 예측과 JSON 변환을 한 CronJob에서 처리해 파드 간 데이터 전달이라는 불필요한 복잡도를 없앤다(KISS). "예측"과 "스케일 결정"은 역할이 다르므로 2번은 별도 CronJob으로 유지한다(관심사 분리).

---

## 7. 인프라 후속 조치 — CronJob이 남긴 권한

CronJob 2개는 **서로 다른 두 권한 체계**를 건드린다. 이 둘을 섞으면 안 된다.

| 무엇 | 어떤 권한 | 왜 |
| --- | --- | --- |
| S3에서 모델·JSON 읽기/쓰기 | **IRSA** (AWS 권한) | 클러스터 **밖** AWS 자원 접근 |
| ScaledObject 수정(patch) | **K8s RBAC** (쿠버네티스 권한) | 클러스터 **안** API 호출 |

| CronJob | 필요 권한 |
| --- | --- |
| `demand-forecast-cronjob` | IRSA: `hailcast-dev-irsa-forecast` (S3 model-artifacts 읽기·쓰기) |
| `keda-scaler-updater-cronjob` | IRSA: S3 읽기 + **RBAC**: `scaledobjects.keda.sh` 리소스에 `get`·`patch` |

- **S3 경로 계약:** 예측 JSON은 모델과 같은 버킷의 `predictions/` prefix 사용(별도 버킷 불필요, KISS).
- **⚠ 통합 오너 확인:** KEDA cron 트리거는 원래 "고정 시간표"용이다. 예측값(동적)을 반영하려면 위처럼 ScaledObject를 주기적으로 patch하는 응용이 된다 — 이 방식과 기존 `predicted_taxi_demand` 메트릭 경로의 관계를 통합 오너와 한 번 정렬할 것.

---

## 8. 시작하기 (dev)

### 8-1. tfstate 부트스트랩 (팀 0순위)

Terraform은 자기 상태 저장소를 스스로 못 만든다(닭-달걀). **버킷 생성 단계만 backend 없이(로컬 상태로) 부트스트랩**한다.

- S3 버킷 `hailcast-dev-tfstate-<랜덤>` (버저닝·암호화 on)
- 잠금은 **S3 자체 잠금**(`use_lockfile = true`) 사용 → **DynamoDB 불필요**
  - ⚠ Terraform **1.11 이상** 필요 (`terraform version`으로 확인)

생성 후 실제 버킷 이름을 `backend.tf`에 반영.

### 8-2. 실행 (dev)

> ⚠ 전제: **Terraform 1.11+**(§8-1의 `use_lockfile`) · AWS 자격증명 설정(`aws configure` 또는 SSO)

```bash
cd envs/dev
terraform init      # 백엔드(S3) 초기화 + 모듈 다운로드
terraform plan      # 변경 미리보기 — 실제 반영 전 반드시 확인
terraform apply     # 실제 적용
terraform destroy   # 데모 끝나면 리소스 내림 (FinOps 규율: 쓸 때만 켠다)
```

민감 값은 tfvars 평문 금지 — 로컬은 `TF_VAR_db_password`, CI는 GitHub Secret으로 주입.

---

## 9. 관련 문서

- [`docs/네이밍규약서.md`](./docs/네이밍규약서.md) — 전체 네이밍 사전 (이름의 단일 진실원천)
