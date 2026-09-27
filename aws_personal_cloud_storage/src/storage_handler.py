import json
import os
import boto3
from botocore.config import Config

# Configure S3 client with Signature Version 4 for presigned URLs
s3_client = boto3.client(
    's3',
    region_name=os.environ.get('AWS_REGION', 'us-east-1'),
    config=Config(signature_version='s3v4')
)

BUCKET_NAME = os.environ.get('BUCKET_NAME')
URL_EXPIRATION = 900  # Presigned URL expires in 15 minutes (900 seconds)

def lambda_handler(event, context):
    http_method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    query_params = event.get('queryStringParameters') or {}
    
    # Extract User ID from Cognito JWT Authorizer context (or default fallback for testing)
    user_id = event.get('requestContext', {}).get('authorizer', {}).get('jwt', {}).get('claims', {}).get('sub', 'default-user')

    try:
        if path == '/files/upload-url' and http_method == 'POST':
            # Request body contains file metadata
            body = json.loads(event.get('body', '{}'))
            file_name = body.get('file_name')
            
            if not file_name:
                return response_format(400, {'message': 'file_name is required in payload'})

            # User files stored under isolated prefix: user_id/file_name
            object_key = f"{user_id}/{file_name}"

            presigned_url = s3_client.generate_presigned_url(
                'put_object',
                Params={
                    'Bucket': BUCKET_NAME,
                    'Key': object_key
                },
                ExpiresIn=URL_EXPIRATION
            )

            return response_format(200, {
                'upload_url': presigned_url,
                'file_key': object_key,
                'expires_in_seconds': URL_EXPIRATION
            })

        elif path == '/files/download-url' and http_method == 'GET':
            file_name = query_params.get('file_name')
            if not file_name:
                return response_format(400, {'message': 'file_name parameter is required'})

            object_key = f"{user_id}/{file_name}"

            presigned_url = s3_client.generate_presigned_url(
                'get_object',
                Params={
                    'Bucket': BUCKET_NAME,
                    'Key': object_key
                },
                ExpiresIn=URL_EXPIRATION
            )

            return response_format(200, {
                'download_url': presigned_url,
                'expires_in_seconds': URL_EXPIRATION
            })

        elif path == '/files' and http_method == 'GET':
            # List user objects
            response = s3_client.list_objects_v2(
                Bucket=BUCKET_NAME,
                Prefix=f"{user_id}/"
            )
            files = []
            if 'Contents' in response:
                for obj in response['Contents']:
                    files.append({
                        'key': obj['Key'],
                        'size_bytes': obj['Size'],
                        'last_modified': obj['LastModified'].isoformat()
                    })

            return response_format(200, {'files': files})

        else:
            return response_format(404, {'message': 'Route not found'})

    except Exception as e:
        return response_format(500, {'error': str(e)})

def response_format(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }
