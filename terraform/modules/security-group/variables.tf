variable "vpc_id" {
  description = "VPC ID the security group belongs to"
  type        = string
}

variable "trusted_ip_cidr" {
  description = "IP, in CIDR form (e.g. 1.2.3.4/32), allowed to SSH in"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming/tagging"
  type        = string
  default     = "project2-os-hardening"
}
