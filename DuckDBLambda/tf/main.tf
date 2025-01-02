# Provider
provider "aws" {
  region = "eu-west-2"
}

# ECR Repository (MAKE SURE THAT THIS IS ALREADY CREATED AND REF IN THIS FILE AS data.aws_ecr_repository.duckdb_lambda)
data "aws_ecr_repository" "duckdb_lambda" {
  name = "duckdb-delta-lambda"
}

# ECR Repository Policy
resource "aws_ecr_repository_policy" "duckdb_lambda_policy" {
  repository = data.aws_ecr_repository.duckdb_lambda.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaECRImageRetrievalPolicy"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# S3 Buckets and their policies
# Create landing bucket - WHERE THE DATA STARTS/LANDS 
resource "aws_s3_bucket" "duckdb_lambda_input_bucket" {
  bucket = "duckdb-lambda-input-bucket"
}

resource "aws_s3_bucket_policy" "input_bucket_policy" {
  bucket = aws_s3_bucket.duckdb_lambda_input_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.duckdb_lambda_input_bucket.arn,
          "${aws_s3_bucket.duckdb_lambda_input_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create Delta Lake bucket - WHERE THE DATA ENDS UP
resource "aws_s3_bucket" "duckdb_lambda_delta_bucket" {
  bucket = "duckdb-lambda-delta-bucket"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "duckdb_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "duckdb_lambda_policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.duckdb_lambda_input_bucket.arn,
          "${aws_s3_bucket.duckdb_lambda_input_bucket.arn}/*",
          aws_s3_bucket.duckdb_lambda_delta_bucket.arn,
          "${aws_s3_bucket.duckdb_lambda_delta_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:*:*:*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [data.aws_ecr_repository.duckdb_lambda.arn]
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "duckdb_processor" {
  function_name = "duckdb-processor"
  role         = aws_iam_role.lambda_role.arn
  timeout      = 900
  memory_size  = 1024
  package_type = "Image"
  image_uri    = "${data.aws_ecr_repository.duckdb_lambda.repository_url}:latest"
  architectures = ["arm64"]
  environment {
    variables = {
      DELTA_BUCKET = aws_s3_bucket.duckdb_lambda_delta_bucket.id
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "duckdb_processor_config" {
  function_name                = aws_lambda_function.duckdb_processor.function_name
  maximum_event_age_in_seconds = 60
  maximum_retry_attempts      = 0 
}

# S3 Event Trigger
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.duckdb_lambda_input_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.duckdb_processor.arn
    events             = ["s3:ObjectCreated:*"]
  }
}

# Lambda Permission for S3
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.duckdb_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.duckdb_lambda_input_bucket.arn
}