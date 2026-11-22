terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "name" { type = string }
variable "location" { type = string }
variable "instance_type" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "allowed_cidrs" { type = list(string) }
variable "app_source" { type = string }
variable "vpc_cidr" { type = string }
variable "upstream_url" {
  type    = string
  default = ""
}
variable "probe_token" {
  type      = string
  sensitive = true
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    description = "Trafico interno de la VPC (prueba upstream)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    description = "ICMP para ping/mtr"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = var.allowed_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf install -y nodejs
    mkdir -p /opt/app
    echo '${base64encode(file(var.app_source))}' | base64 -d > /opt/app/server.js
    cat > /etc/systemd/system/probe.service <<UNIT
    [Unit]
    Description=latency probe
    After=network.target
    [Service]
    Environment=LOCATION=${var.location}
    Environment=PROBE_TOKEN=${var.probe_token}
    Environment=UPSTREAM_URL=${var.upstream_url}
    ExecStart=/usr/bin/node /opt/app/server.js
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    mkdir -p /opt/app/certs
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=probe" -keyout /opt/app/certs/key.pem -out /opt/app/certs/cert.pem
    systemctl daemon-reload
    systemctl enable --now probe
  EOT

  tags = { Name = var.name }
}

output "public_ip" { value = aws_instance.this.public_ip }
output "public_dns" { value = aws_instance.this.public_dns }
output "private_ip" { value = aws_instance.this.private_ip }
