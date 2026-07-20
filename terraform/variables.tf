variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "trusted_ip_cidr" {
  description = "IP in CIDR form, allowed to SSH in"
  type        = string
}

variable "project_name" {
  description = "Project name used for naming/tagging"
  type        = string
  default     = "project2-os-hardening"
}
