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
  vpc_security_group_ids = [aws_security_group.sg-example.id]
  user_data     = <<-EOF
              #!/bin/bash
              echo "${file("index.html")}" > index.html
              nohup busybox httpd -f -p 8080 &
              EOF
  tags = {
    "source" = "terraform"
    "Name"   = "tf-ami-example"
  }
}

resource "aws_security_group" "sg-example" {
  name = "terraform-sg-example"
  description = "Allow public access"
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    "source" = "terraform"
    "Name"   = "terraform-sg-example"
  }
}