output "web_public_ip" {
  description = "The public IP address of the EC2 instance"
  value       = aws_eip.one.public_ip
  depends_on  = [aws_eip.one]
}

output "database_endpoint" {
  description = "The endpoint of the database"
  value       = aws_db_instance.db_instance.address
}

output "database_port" {
  description = "The port of the database"
  value       = aws_db_instance.db_instance.port
}
