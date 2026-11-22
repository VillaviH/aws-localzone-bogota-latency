output "bogota_ip" { value = module.bogota.public_ip }
output "virginia_ip" { value = module.virginia.public_ip }
output "probe_token" {
  value     = random_password.probe_token.result
  sensitive = true
}
output "cloudfront_domain" { value = var.enable_cloudfront ? aws_cloudfront_distribution.cdn[0].domain_name : null }
