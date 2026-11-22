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
  vpc_cidr      = aws_vpc.use1.cidr_block
  # La app de Bogotá consulta a Virginia por IP privada (simula una BD en la región padre)
  upstream_url = var.enable_upstream_test ? "http://${module.virginia.private_ip}" : ""
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
  vpc_cidr      = aws_vpc.use1.cidr_block
}

# ---------- CloudFront delante de Virginia ----------
# El token se valida en el borde (CloudFront Function) y se reenvía al origen como header.
resource "aws_cloudfront_function" "guard" {
  count   = var.enable_cloudfront ? 1 : 0
  name    = "probe-token-guard"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var h = event.request.headers;
      if (!h['x-probe-token'] || h['x-probe-token'].value !== '${random_password.probe_token.result}') {
        return { statusCode: 403, statusDescription: 'Forbidden' };
      }
      return event.request;
    }
  JS
}

resource "aws_cloudfront_cache_policy" "respect_origin" {
  count       = var.enable_cloudfront ? 1 : 0
  name        = "probe-respect-origin"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 3600
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_distribution" "cdn" {
  count       = var.enable_cloudfront ? 1 : 0
  enabled     = true
  comment     = "latency probe: CloudFront -> Virginia"
  price_class = "PriceClass_All" # incluye bordes de Sudamérica

  origin {
    domain_name = module.virginia.public_dns
    origin_id   = "virginia"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
    custom_header {
      name  = "x-probe-token"
      value = random_password.probe_token.result
    }
  }

  default_cache_behavior {
    target_origin_id       = "virginia"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = aws_cloudfront_cache_policy.respect_origin[0].id
    compress               = false
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.guard[0].arn
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate { cloudfront_default_certificate = true }
}
