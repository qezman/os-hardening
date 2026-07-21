variable "instances" {
  description = "Map of instances to create, keyed by name, with their AMI & OS type"
  type = map(object({
    ami     = string
    os_type = string
  }))

  default = {
    "ubuntu-1" = { ami = "ami-0d001f8052688dc45", os_type = "ubuntu" }
    "ubuntu-2" = { ami = "ami-0d001f8052688dc45", os_type = "ubuntu" }
    "ubuntu-3" = { ami = "ami-0d001f8052688dc45", os_type = "ubuntu" }
    "amzn-1"   = { ami = "ami-0f303bae6b670e0ed", os_type = "amazon-linux" }
    "amzn-2"   = { ami = "ami-0f303bae6b670e0ed", os_type = "amazon-linux" }
  }
}

variable "instance_type" {
  description = "EC2 instance type for all fleet members"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet to launch instances into"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID to attach to instances"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "IAM instance profile name for compliance report uploads"
  default     = string
}

variable "project_name" {
  description = "Project name used for naming/tagging"
  type        = string
  default     = "project2-os-hardening"
}
