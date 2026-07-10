# envs/dev - backend.tf (골격)
terraform {
  backend "s3" {
    bucket       = "hailcast-dev-tfstate-9dcb"
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}