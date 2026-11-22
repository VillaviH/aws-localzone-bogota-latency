variable "aws_profile" {
  description = "Perfil de AWS CLI a usar. null usa la cadena de credenciales por defecto."
  type        = string
  default     = null
}

variable "local_zone" {
  type    = string
  default = "us-east-1-bog-1a"
}

variable "virginia_az" {
  description = "AZ regional. Misma zona padre de la Local Zone (us-east-1b)."
  type        = string
  default     = "us-east-1b"
}

variable "instance_type" {
  description = "Tipo más barato disponible en la Local Zone de Bogotá (no hay t3)."
  type        = string
  default     = "c7i.large"
}

variable "allowed_cidrs" {
  description = "CIDRs con acceso al puerto 80 e ICMP. Abierto porque la IP del móvil cambia; la app exige un token (x-probe-token)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cloudfront" {
  description = "Crea una distribución de CloudFront delante de Virginia para compararla con la Local Zone."
  type        = bool
  default     = true
}

variable "enable_upstream_test" {
  description = "Permite que la app de Bogotá consulte a Virginia por IP privada (simula una BD en la región padre)."
  type        = bool
  default     = true
}
