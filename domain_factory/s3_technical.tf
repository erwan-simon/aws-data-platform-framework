resource "aws_s3_bucket" "technical" {
  bucket = "${replace(local.environment_name, "_", "-")}-technical"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "technical" {
  bucket = aws_s3_bucket.technical.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "technical" {
  bucket = aws_s3_bucket.technical.id

  rule {
    id = "delete"
    expiration {
      days = 7
    }
    status = "Enabled"
    filter {
      prefix = "/${local.athena_workgroup_output_key}"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "technical" {
  bucket = aws_s3_bucket.technical.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "technical" {
  bucket = aws_s3_bucket.technical.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "technical" {
  bucket = aws_s3_bucket.technical.id
  name   = "EntireBucket"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 360
  }
}
