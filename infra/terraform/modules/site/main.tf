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
variable "package_source" { type = string }
variable "vpc_cidr" { type = string }
variable "bucket_name" { type = string }
variable "bucket_arn" { type = string }
variable "parent_bucket_name" {
  description = "Bucket regional adicional (solo Bogotá): permite probar una app en la zona con datos en la región padre."
  type        = string
  default     = ""
}
variable "parent_bucket_arn" {
  type    = string
  default = ""
}
variable "bucket_kind" {
  description = "directory (S3 en Local Zone) o general (S3 regional)"
  type        = string
}
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

# Cada instancia solo puede usar su propio bucket. SSM permite inspeccionarla sin SSH.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.name}-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "s3" {
  statement {
    actions   = var.bucket_kind == "directory" ? ["s3express:CreateSession"] : ["s3:GetObject", "s3:PutObject"]
    resources = var.bucket_kind == "directory" ? [var.bucket_arn] : ["${var.bucket_arn}/*"]
  }
  dynamic "statement" {
    for_each = var.parent_bucket_arn != "" ? [1] : []
    content {
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["${var.parent_bucket_arn}/*"]
    }
  }
}

resource "aws_iam_role_policy" "s3" {
  name   = "bucket-access"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.s3.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.this.name
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.this.name
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
    dnf install -y nodejs22 nodejs22-npm || dnf install -y nodejs20 nodejs20-npm || dnf install -y nodejs npm
    mkdir -p /opt/app
    echo '${base64encode(file(var.package_source))}' | base64 -d > /opt/app/package.json
    (cd /opt/app && npm install --omit=dev)
    echo '${base64encode(file(var.app_source))}' | base64 -d > /opt/app/server.js
    cat > /etc/systemd/system/probe.service <<UNIT
    [Unit]
    Description=latency probe
    After=network.target
    [Service]
    Environment=LOCATION=${var.location}
    Environment=PROBE_TOKEN=${var.probe_token}
    Environment=UPSTREAM_URL=${var.upstream_url}
    Environment=S3_BUCKET=${var.bucket_name}
    Environment=S3_KIND=${var.bucket_kind}
    Environment=S3_PARENT_BUCKET=${var.parent_bucket_name}
    Environment=AWS_REGION=us-east-1
    ExecStart=/usr/bin/env node /opt/app/server.js
    WorkingDirectory=/opt/app
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
output "instance_id" { value = aws_instance.this.id }
output "private_ip" { value = aws_instance.this.private_ip }
