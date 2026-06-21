resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
  tags   = var.tags
  # force_destroy intentionally left false (default): this bucket holds real
  # documents/seed data. If it's ever targeted for destroy by mistake,
  # Terraform should fail loudly (BucketNotEmpty) instead of silently
  # deleting everything in it.
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enc" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "ver" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
