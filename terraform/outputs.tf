output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_id" {
  value = module.network.public_subnet_id
}

output "security_group_id" {
  value = module.security_group.security_group_id
}

output "compliance_bucket_name" {
  value = module.compliance_bucket.bucket_name
}

output "instance_public_ips" {
  value = module.ec2_fleet.instance_public_ips
}

output "private_key_path" {
  value = module.ec2_fleet.private_key_path
}
