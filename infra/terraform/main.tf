terraform {
  required_version = ">= 1.5"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = var.aws_profile
}

resource "random_password" "probe_token" {
  length  = 24
  special = false
}

locals {
  app_source = "${path.module}/../../app/server.js"
}

# us-east-1: una VPC con subred regional y subred en la Local Zone
resource "aws_vpc" "use1" {
  cidr_block           = "10.10.0.0/24"
  enable_dns_hostnames = true
  tags                 = { Name = "lz-bog-demo" }
}

resource "aws_internet_gateway" "use1" {
  vpc_id = aws_vpc.use1.id
}

resource "aws_route_table" "use1" {
  vpc_id = aws_vpc.use1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.use1.id
  }
}

resource "aws_subnet" "virginia" {
  vpc_id                  = aws_vpc.use1.id
  cidr_block              = "10.10.0.0/26"
  availability_zone       = var.virginia_az
  map_public_ip_on_launch = true
  tags                    = { Name = "virginia" }
}

resource "aws_subnet" "bogota" {
  vpc_id                  = aws_vpc.use1.id
  cidr_block              = "10.10.0.64/26"
  availability_zone       = var.local_zone
  map_public_ip_on_launch = true
  tags                    = { Name = "bogota-lz" }
}

resource "aws_route_table_association" "virginia" {
  subnet_id      = aws_subnet.virginia.id
  route_table_id = aws_route_table.use1.id
}

resource "aws_route_table_association" "bogota" {
  subnet_id      = aws_subnet.bogota.id
  route_table_id = aws_route_table.use1.id
}

module "bogota" {
  source        = "./modules/site"
  name          = "probe-bogota-lz"
  location      = "bogota-lz"
  instance_type = var.instance_type
  vpc_id        = aws_vpc.use1.id
  subnet_id     = aws_subnet.bogota.id
  allowed_cidrs = var.allowed_cidrs
  app_source    = local.app_source
  probe_token   = random_password.probe_token.result
}

module "virginia" {
  source        = "./modules/site"
  name          = "probe-virginia"
  location      = "us-east-1"
  instance_type = var.instance_type
  vpc_id        = aws_vpc.use1.id
  subnet_id     = aws_subnet.virginia.id
  allowed_cidrs = var.allowed_cidrs
  app_source    = local.app_source
  probe_token   = random_password.probe_token.result
}
