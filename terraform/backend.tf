terraform {
  backend "s3" {
    bucket         = "os-hardening-tfstate-560205084952"
    key            = "project2/terraform.tfstate"
    region         = "us-east-1"
    profile        = "project2"
    dynamodb_table = "os-hardening-tf-lock"
  }
}
