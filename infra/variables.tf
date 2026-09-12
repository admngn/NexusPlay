variable "aws_region" {
  description = "AWS region cible (Learner Lab restreint à us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Type EC2 pour les 3 instances (t4g.micro - ARM64)"
  type        = string
  default     = "t4g.micro"
}

variable "key_name" {
  description = "Nom de la key pair SSH existante"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs autorisés pour SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "frontend_port" {
  description = "Port d'écoute du frontend"
  type        = number
  default     = 3000
}

variable "backend_port" {
  description = "Port d'écoute du backend"
  type        = number
  default     = 8080
}
