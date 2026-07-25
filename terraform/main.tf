# Network layer: VPC, public subnet, IGW, route table.
module "network" {
  source = "./modules/network"

  project_name = var.project_name
}

# SSH-only sg, scoped to a single trusted IP.
# Allows oth port 22 (pre-hardening) and 2222 (post-hardening) so the
# hardening script can migrate SSH port without locking us out mid-change.
module "security_group" {
  source = "./modules/security-group"

  vpc_id          = module.network.vpc_id
  trusted_ip_cidr = var.trusted_ip_cidr
  project_name    = var.project_name
}

# S3 bucket for compliance reports + least-privilege IAM role/instance
# profile that EC2 instances assume to upload their own reports.
module "compliance_bucket" {
  source = "./modules/compliance-bucket"

  bucket_suffix = "560205084952"
}

# The 5-instance fleet (3 Ubuntu, 2 Amazon Linux) via for_each
module "ec2_fleet" {
  source = "./modules/ec2-fleet"

  subnet_id                 = module.network.public_subnet_id
  security_group_id         = module.security_group.security_group_id
  iam_instance_profile_name = module.compliance_bucket.aws_iam_instance_profile_name
}

