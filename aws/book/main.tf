terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.65.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "ami-example" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  tags = {
    "source" = "terraform"
    "Name"   = "tf-ami-example"
  }
}