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

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}

# Запросить информацию о своем облаке VPC по умолчанию
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  # Ищем подсети внутри облака VPC по умолчанию
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group" "sg-example" {
  name        = "terraform-sg-example"
  description = "Allow public access"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    "source" = "terraform"
    "Name"   = "tf-sg-example"
  }
}

resource "aws_launch_configuration" "launch-example" {
  name_prefix     = "tf-launch-example-"
  image_id        = "ami-0c55b159cbfafe1f0"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.sg-example.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "${file("index.html")}" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  # Требуется при использовании группы автомасштабирования
  lifecycle {
    create_before_destroy = true
  }
}

# ASG - группа автомасштабирования
resource "aws_autoscaling_group" "asg-example" {
  launch_configuration = aws_launch_configuration.launch-example.name
  # Определяем подсети VPC, в которых должны быть развернуты серверы EC2
  vpc_zone_identifier = data.aws_subnet_ids.default.ids
  # итегрируем ASG и ALB
  target_group_arns = [aws_lb_target_group.asg.arn]
  # ASG будет проверять работоспособность целевой группы
  health_check_type = "ELB" # EC2

  min_size = 2
  max_size = 5

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Группу безопасности специально для балансировщика нагрузки
resource "aws_security_group" "alb-example" {
  name = "terraform-alb-example"
  # Разрешаем все входящие HTTP-запросы
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Разрешаем все исходящие запросы
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Целевая группа для ASG
resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  # Шлем запросы для проверки работоспособности серверов
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ALB - балансировщик нагрузки
resource "aws_lb" "lb-example" {
  name               = "terraform-asg-example"
  load_balancer_type = "application"
  # Использования всех подсетей в облаке VPC по умолчанию с помощью источника данных aws_subnet_ids
  subnets         = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.alb-example.id]
}

# прослушиватель для ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lb-example.arn
  port              = 80
  protocol          = "HTTP"

  # По умолчанию возвращает простую страницу с кодом 404
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

# правило прослушивателя: шлем все запросы, соответствующие любому пути, к целевой группе с ASG внутри.

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# Выводим доменное имя ALB
output "alb_dns_name" {
  value       = aws_lb.lb-example.dns_name
  description = "The domain name of the load balancer"
}