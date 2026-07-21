# stores each instance's generated compliance report
resource "aws_s3_bucket" "compliance_reports" {
  bucket = "${var.project_name}-reports-${var.bucket_suffix}"

  tags = {
    Name    = "${var.project_name}-reports"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_versioning" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

# block all four public-access vectors
resource "aws_s3_bucket_public_access_block" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Trust policy: only the EC2 service can assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}


# Role name MUST match the "project2-*" pattern 
# the IAM policy only allows managing roles under that prefix.
resource "aws_iam_role" "ec2_compliance-role" {
  name               = "project2-ec2-compliance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Project = var.project_name
  }
}

data "aws_iam_policy_document" "s3_upload" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.compliance_reports.arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_upload" {
  name   = "project2-s3_upload-policy"
  role   = aws_iam_role.ec2_compliance-role.id
  policy = data.aws_iam_policy_document.s3_upload.json
}

# What actually gets attached to an EC2 instance to grant it this role
resource "aws_iam_instance_profile" "ec2_compliance_profile" {
  name = "project2-ec2-compliance-profile"
  role = aws_iam_role.ec2_compliance-role.name
}
