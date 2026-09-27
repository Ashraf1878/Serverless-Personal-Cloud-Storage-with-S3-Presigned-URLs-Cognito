terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "storage_bucket_prefix" {
  description = "Unique prefix for personal storage S3 bucket"
  type        = string
  default     = "personal-cloud-storage-bucket"
}

# 1. Private S3 Bucket with Lifecycle Rule
resource "aws_s3_bucket" "cloud_storage" {
  bucket        = "${var.storage_bucket_prefix}-${random_string.suffix.result}"
  force_destroy = true
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket                  = aws_s3_bucket.cloud_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  bucket = aws_s3_bucket.cloud_storage.id

  rule {
    id     = "archive-old-files"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

# 2. Amazon Cognito User Pool for Authentication
resource "aws_cognito_user_pool" "user_pool" {
  name = "personal_cloud_user_pool"
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "personal_cloud_app_client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# 3. IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "storage_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "s3_access_policy" {
  name = "storage_lambda_s3_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cloud_storage.arn,
          "${aws_s3_bucket.cloud_storage.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Archive Lambda Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/storage_handler.py"
  output_path = "${path.module}/lambda.zip"
}

# 4. Lambda Function
resource "aws_lambda_function" "storage_api" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "PersonalCloudStorageHandler"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "storage_handler.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cloud_storage.id
    }
  }
}

# 5. API Gateway (HTTP API v2)
resource "aws_apigatewayv2_api" "http_api" {
  name          = "personal-cloud-storage-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.client.id]
    issuer   = "https://${aws_cognito_user_pool.user_pool.endpoint}"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.storage_api.invoke_arn
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "upload_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /files/upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "download_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /files/download-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "list_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /files"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.storage_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.cloud_storage.id
}
