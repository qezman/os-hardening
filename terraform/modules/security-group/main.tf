resource "aws_security_group" "ssh_access" {
  name        = "${var.project_name}-ssh-sg"
  description = "Allow SSH on port 22 & hardened port 2222, scoped to trusted IP"
  vpc_id      = var.vpc_id

# Pre-hardening SSH port - open only to my IP
  # ingress {
  #   description = "SSH - default port - pre-hardening"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = [var.trusted_ip_cidr]
  # }

  # Post-hardening SSH port - kept open to prevent lockout lockout.
  ingress {
    description = "SSH - hardened custom port"
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = [var.trusted_ip_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-ssh-sg"
    Project = var.project_name
  }
}
