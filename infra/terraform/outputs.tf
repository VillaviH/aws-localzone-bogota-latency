output "bogota_ip" { value = module.bogota.public_ip }
output "virginia_ip" { value = module.virginia.public_ip }
output "probe_token" {
  value     = random_password.probe_token.result
  sensitive = true
}
output "bogota_alb" { value = module.alb_bogota.dns_name }
output "virginia_alb" { value = module.alb_virginia.dns_name }
output "bogota_bucket" { value = aws_s3_directory_bucket.bogota.bucket }
output "virginia_bucket" { value = aws_s3_bucket.virginia.bucket }
