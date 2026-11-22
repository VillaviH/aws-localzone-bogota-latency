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

resource "random_id" "bucket" {
  byte_length = 4
}

data "aws_availability_zone" "lz" {
  name                   = var.local_zone
  all_availability_zones = true
}

locals {
  bucket_lz = "lzprobe-${random_id.bucket.hex}--${data.aws_availability_zone.lz.zone_id}--x-s3"
  bucket_va = "lzprobe-${random_id.bucket.hex}-use1"

  app_source     = "${path.module}/../../app/server.js"
  package_source = "${path.module}/../../app/package.json"
}

# Bogotá: bucket de directorio en la Local Zone (S3 One Zone-IA)
resource "aws_s3_directory_bucket" "bogota" {
  bucket          = local.bucket_lz
  data_redundancy = "SingleLocalZone"
  force_destroy   = true
  location {
    name = data.aws_availability_zone.lz.zone_id
    type = "LocalZone"
  }
}

# Virginia: bucket regional; la app escribe con la clase ONEZONE_IA para comparar igual
resource "aws_s3_bucket" "virginia" {
  bucket        = local.bucket_va
  force_destroy = true
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

resource "aws_subnet" "virginia_b" {
  vpc_id                  = aws_vpc.use1.id
  cidr_block              = "10.10.0.128/26"
  availability_zone       = var.virginia_az_2
  map_public_ip_on_launch = true
  tags                    = { Name = "virginia-b" }
}

resource "aws_route_table_association" "virginia_b" {
  subnet_id      = aws_subnet.virginia_b.id
  route_table_id = aws_route_table.use1.id
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
  source         = "./modules/site"
  name           = "probe-bogota-lz"
  location       = "bogota-lz"
  instance_type  = var.instance_type
  vpc_id         = aws_vpc.use1.id
  subnet_id      = aws_subnet.bogota.id
  allowed_cidrs  = var.allowed_cidrs
  app_source     = local.app_source
  package_source = local.package_source
  probe_token    = random_password.probe_token.result
  vpc_cidr       = aws_vpc.use1.cidr_block
  bucket_name    = aws_s3_directory_bucket.bogota.bucket
  bucket_arn     = aws_s3_directory_bucket.bogota.arn
  bucket_kind    = "directory"
  # Permite medir la app de Bogotá contra el bucket regional (datos en la región padre)
  parent_bucket_name = aws_s3_bucket.virginia.bucket
  parent_bucket_arn  = aws_s3_bucket.virginia.arn
  # La app de Bogotá consulta a Virginia por IP privada (simula una BD en la región padre)
  upstream_url = var.enable_upstream_test ? "http://${module.virginia.private_ip}" : ""
}

module "virginia" {
  source         = "./modules/site"
  name           = "probe-virginia"
  location       = "us-east-1"
  instance_type  = var.instance_type
  vpc_id         = aws_vpc.use1.id
  subnet_id      = aws_subnet.virginia.id
  allowed_cidrs  = var.allowed_cidrs
  app_source     = local.app_source
  package_source = local.package_source
  probe_token    = random_password.probe_token.result
  vpc_cidr       = aws_vpc.use1.cidr_block
  bucket_name    = aws_s3_bucket.virginia.bucket
  bucket_arn     = aws_s3_bucket.virginia.arn
  bucket_kind    = "general"
}

# Balanceadores de carga (ELB): uno en la Local Zone y otro en Virginia
module "alb_bogota" {
  source        = "./modules/alb"
  name          = "probe-alb-bogota"
  vpc_id        = aws_vpc.use1.id
  subnet_ids    = [aws_subnet.bogota.id]
  instance_id   = module.bogota.instance_id
  allowed_cidrs = var.allowed_cidrs
}

module "alb_virginia" {
  source        = "./modules/alb"
  name          = "probe-alb-virginia"
  vpc_id        = aws_vpc.use1.id
  subnet_ids    = [aws_subnet.virginia.id, aws_subnet.virginia_b.id]
  instance_id   = module.virginia.instance_id
  allowed_cidrs = var.allowed_cidrs
}
