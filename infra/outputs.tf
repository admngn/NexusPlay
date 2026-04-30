output "nginx_public_ip" {
  description = "IP publique du reverse proxy nginx primaire"
  value       = aws_instance.nginx.public_ip
}

output "nginx_private_ip" {
  description = "IP privée du reverse proxy nginx primaire"
  value       = aws_instance.nginx.private_ip
}

output "nginx2_public_ip" {
  description = "IP publique du reverse proxy nginx secondaire (LB redondance)"
  value       = aws_instance.nginx2.public_ip
}

output "nginx2_private_ip" {
  description = "IP privée du reverse proxy nginx secondaire"
  value       = aws_instance.nginx2.private_ip
}

output "frontend_public_ip" {
  description = "IP publique du frontend"
  value       = aws_instance.frontend.public_ip
}

output "frontend_private_ip" {
  description = "IP privée du frontend (utilisée par nginx en upstream)"
  value       = aws_instance.frontend.private_ip
}

output "backend_public_ip" {
  description = "IP publique du backend"
  value       = aws_instance.backend.public_ip
}

output "backend_private_ip" {
  description = "IP privée du backend (utilisée par nginx en upstream)"
  value       = aws_instance.backend.private_ip
}
