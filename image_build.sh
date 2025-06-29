#!/bin/bash

AWS_ACCOUNT_ID="887998956998" # Replace with your actual AWS account ID
AWS_REGION="us-east-1"
SERVER_REPO_NAME="external_secrets/eso"
VERSION="v0.18.0"
SERVER_ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${SERVER_REPO_NAME}"

# Log into ECR
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Pull image
docker pull --platform linux/amd64 ghcr.io/external-secrets/external-secrets:v0.18.0


# Tag image
docker tag ghcr.io/external-secrets/external-secrets:v0.18.0 ${SERVER_ECR_URL}:${VERSION}

# Push image
echo "Pushing server..."
docker push ${SERVER_ECR_URL}:${VERSION}

echo "Image successfully built, tagged as ${VERSION}, and pushed to ${SERVER_ECR_URL}"
