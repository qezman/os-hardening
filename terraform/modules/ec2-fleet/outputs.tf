output "instance_ids" {
  description = "Map of instance names to their IDs"
  value       = { for k, v in aws_instance.fleet : k => v.id }
}

output "instance_public_ips" {
  description = "Map of instance names to their public IPs"
  value       = { for k, v in aws_instance.fleet : k => v.public_ip }
}

output "private_key_path" {
  description = "Path to the generated private key for SSH access"
  value       = local_file.private_key.filename
}
