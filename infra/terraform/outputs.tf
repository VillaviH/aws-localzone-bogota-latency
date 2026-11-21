output "bogota_ip" { value = module.bogota.public_ip }
output "virginia_ip" { value = module.virginia.public_ip }
output "probe_token" {
  value     = random_password.probe_token.result
  sensitive = true
}
