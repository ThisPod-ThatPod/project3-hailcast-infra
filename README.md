# project3-hailcast-infra
hailcast 인프라 (Terraform · AWS 서울) · 담당: 그룹 A (유현상·이미선)

## 구조
- envs/dev : 조립·상태(backend). modules를 호출
- modules  : network / storage / eks / data / security
## 배포
terraform init → plan → apply (state: S3 백엔드 + DynamoDB 락)
## 참고
네이밍 규약 v2 · 보안 규약 v2 · AWS 리소스 사전 (노션)
