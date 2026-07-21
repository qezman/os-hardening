variable "project_name" {
  description = "Project name used for naming/tagging"
  type        = string
  default     = "project2-os-hardening"
}

variable "bucket_suffix" {
  description = "Unique suffix for the bucket name (e.g account ID) to avoid global name collisions"
  type        = string
}
