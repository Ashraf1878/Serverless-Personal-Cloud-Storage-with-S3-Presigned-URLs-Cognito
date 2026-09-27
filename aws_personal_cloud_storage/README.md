# Secure Personal Cloud Storage on AWS (S3 Presigned URLs + Serverless)

![AWS Architecture](https://img.shields.io/badge/AWS-S3%20%7C%20API%20Gateway%20%7C%20Lambda%20%7C%20Cognito-orange?logo=amazon-aws)
![Terraform](https://img.shields.io/badge/IaC-Terraform-purple?logo=terraform)
![Python](https://img.shields.io/badge/Runtime-Python%203.11-blue?logo=python)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-blue?logo=githubactions)

A secure, high-performance, and completely serverless Personal Cloud Storage solution built on AWS. Rather than proxying large binary files through API Gateway or Lambda, this architecture utilizes **S3 Presigned URLs** to enable fast, direct browser-to-S3 uploads and downloads without exposing public bucket access.

## 📐 Architecture Overview
- **User Authentication**: Amazon Cognito User Pools for issuing JWT identity tokens.
- **API Orchestration**: Amazon API Gateway (HTTP API v2) integrated with a Cognito JWT Authorizer.
- **Presigned URL Generation**: AWS Lambda (Python 3.11) generates short-lived, signed S3 URLs for secure direct uploads (`PUT`) and downloads (`GET`).
- **Storage Layer**: Amazon S3 private storage bucket with encryption-at-rest (KMS/S3-Managed) and lifecycle transition rules to Glacier Instant Retrieval.
- **Security & Permissions**: AWS IAM execution policies strict to the Principle of Least Privilege.

## 📁 Repository Structure
```
.
├── .github/
│   └── workflows/
│       └── deploy.yml      # GitHub Actions CI/CD Pipeline
├── src/
│   └── storage_handler.py  # Lambda function generating Presigned URLs
├── terraform/
│   └── main.tf             # IaC defining S3, Cognito, API Gateway, Lambda & IAM
└── README.md               # GitHub Portfolio Documentation
```

## 🔗 API Specifications

| Method | Endpoint | Query Params / Body | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/files/upload-url` | `{"file_name": "photo.png"}` | Generates a 15-minute S3 PUT presigned URL for direct upload |
| `GET` | `/files/download-url` | `?file_name=photo.png` | Generates a 15-minute S3 GET presigned URL for direct download |
| `GET` | `/files` | None | Lists all uploaded user files in S3 |

## 🚀 Getting Started

### Prerequisites
- [AWS CLI](https://aws.amazon.com/cli/) configured
- [Terraform](https://www.terraform.io/) >= v1.5.0

### Infrastructure Provisioning
```bash
cd terraform
terraform init
terraform plan -var="storage_bucket_prefix=my-private-cloud-storage"
terraform apply -var="storage_bucket_prefix=my-private-cloud-storage"
```

### GitHub Actions Deployment
Add the following secrets under **Settings > Secrets and variables > Actions**:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `STORAGE_BUCKET_PREFIX`
