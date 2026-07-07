# envs/dev - backend.tf (골격)
terraform {
  backend "s3" {
    bucket         = "tfstate-bucket-9dcbc7fe"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "hailcast-dev-tfstate-lock"
    encrypt        = true
  }
}