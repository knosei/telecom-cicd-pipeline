
#!/bin/bash

set -e

AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="627073650114"
IMAGE_TAG="YOUR_IMAGE_TAG"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${ECR_REGISTRY}/telecom-cicd-pipeline:${IMAGE_TAG}"

echo "Retrieving application secrets..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id telecom-cicd/app \
    --region "${AWS_REGION}" \
    --query SecretString \
    --output text)

mkdir -p /opt/telecom-cicd
chmod 700 /opt/telecom-cicd

printf '%s' "$SECRET_JSON" | python3 -c '
import json, sys

data = json.load(sys.stdin)

with open("/opt/telecom-cicd/app.env", "w") as f:
    for key, value in data.items():
        f.write(f"{key}={value}\n")
'

chmod 600 /opt/telecom-cicd/app.env

echo "Logging into Amazon ECR..."

aws ecr get-login-password \
    --region "${AWS_REGION}" \
    | docker login \
    --username AWS \
    --password-stdin "${ECR_REGISTRY}"

echo "Pulling Docker image..."

docker pull "${IMAGE}"

echo "Starting application..."

docker run -d \
    --name telecom-cicd-pipeline \
    --restart unless-stopped \
    --env-file /opt/telecom-cicd/app.env \
    -p 5000:5000 \
    "${IMAGE}"

echo "Application deployment completed."
