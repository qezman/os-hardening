# creates 5 instances without 5 repeated resource blocks using for_each
resource "aws_instance" "fleet" {
  for_each = var.instances

  ami                    = each.value.ami
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.fleet_key.key_name
  iam_instance_profile   = var.iam_instance_profile_name

  tags = {
    name    = "${var.project_name}-${each.key}"
    Project = var.project_name
    osType  = each.value.os_type
  }
}

resource "aws_eip" "fleet" {
  for_each = var.instances

  instance = aws_instance.fleet[each.key].id
  domain = "vpc"


  tags = {
    Name    = "${var.project_name}-${each.key}-eip"
    Project = var.project_name
  }
}

# Registers the public half with AWS so it's injected at instance boot.
resource "aws_key_pair" "fleet_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.fleet_key.public_key_openssh
}

# Generates an RSA keypair inside Terraform state
resource "tls_private_key" "fleet_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# read-only (0400)
resource "local_file" "private_key" {
  content  = tls_private_key.fleet_key.private_key_pem
  filename = "${path.module}/../../${var.project_name}-key.pem"
  file_permission = "0400"
}
