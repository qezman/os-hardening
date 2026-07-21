output "bucket_name" {
  value = aws_s3_bucket.compliance_reports.bucket
}

output "aws_iam_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_compliance_profile.name
}
