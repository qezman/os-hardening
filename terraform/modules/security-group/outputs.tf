output "security_group_id" {
  description = "ID of the SSH sg"
  value       = aws_security_group.ssh_access.id
}
