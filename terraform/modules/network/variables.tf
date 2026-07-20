variable "project_name" {
  description = "Project name used for resource naming/tagging"
  type        = string
  default     = "project2-os-hardening"
}

variable "vpc_cidr" {
  description = "CIDR block for the vpc"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "availability_zone" {
  description = "AZ to place public subnet in"
  type        = string
  default     = "us-east-1a"
}
