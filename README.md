# External-Secrets-Operator-on-AWS

## Prerequisites
- AWS account with appropriate permissions
- Kubernetes cluster (EKS or other distribution)
- kubectl configured to access your cluster
- AWS CLI configured with appropriate credentials
- Helm installed (v3+)

## Step 1: Install External Secrets Operator using Helm
### For internal ECR, Pull, tag and push the External Secrets Operator image to ECR:
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 
docker pull ghcr.io/external-secrets/external-secrets:v0.18.0
docker tag ghcr.io/external-secrets/external-secrets:v0.18.0 123456789012.dkr.ecr.us-east-1.amazonaws.com/external-secrets:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/external-secrets:latest
```

### Add the External Secrets Operator Helm repository:
```bash
helm repo add external-secrets https://charts.external-secrets.io
```
### Update your local Helm chart repository cache:
```bash
helm repo update
```
### Install the External Secrets Operator using Helm:
```bash
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --reuse-values \
  --set image.repository=123456789012.dkr.ecr.us-east-1.amazonaws.com/external-secrets \
  --set image.tag=latest \
  --set installCRDs=true

kubectl rollout restart deployment external-secrets-webhook \
  -n external-secrets

```
### Verify the installation:
```bash
kubectl get pods -n external-secrets
```
you should see the External Secrets Operator pod running.

## Step 2: Configure AWS Secrets Manager
### Create an IAM policy (eso_policy.json)for the External Secrets Operator:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecrets",
                "secretsmanager:BatchGetSecretValue",
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:ListSecretVersionIds",
                "ssm:GetParameter*"
            ],
            "Resource": "*"
        }
    ]
}
        
```
### Create an IAM policy in AWS:
```bash
aws iam create-policy \
--policy-name ExternalSecretsOperatorPolicy \
--policy-document file://eso-policy.json
```
Note the ARN of the created policy for the next step.

### Create an IAM role for the External Secrets Operator service account:
```bash
aws iam create-role \
--role-name ExternalSecretsOperatorRole \
--policy-arn arn:aws:iam::123456789012:policy/ExternalSecretsOperatorPolicy
```

## Step 3: Create an IAM role for Service Account (IRSA):
### Create IAM OIDC provider for your EKS cluster:
```bash
# Get cluster OIDC issuer URL
OIDC_URL=$(aws eks describe-cluster --name <clustername> --query "cluster.identity.oidc.issuer" --output text | cut -d/ -f3-)

# Check if OIDC provider already exists
aws iam list-open-id-connect-providers | grep $OIDC_URL || \
aws iam create-open-id-connect-provider \
  --url https://$OIDC_URL \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list $(openssl s_client -connect $OIDC_URL:443 -showcerts < /dev/null 2>/dev/null | openssl x509 -fingerprint -noout | cut -d= -f2 | tr -d ':')    
```
### Create an IAM Trusted policy(eso-trust-policy.json):
```bash
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/E3F2Cxxxxx"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/E3F2Cxxxxx:sub": "system:serviceaccount:external-secrets:external-secrets",
          "oidc.eks.us-east-1.amazonaws.com/id/E3F2Cxxxxxxx:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}

```

## Step 4: Create a Kubernetes Service Account (sa.yaml):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-operator
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ExternalSecretsOperatorRole
```
## Step 5: Create a Kubernetes ClusterSecretStore (secretstore.yaml):apiVersion: 
```yaml
external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secret-store
spec: 
  provider:
    aws:
      region: us-east-1
      auth:
      jwt:  
      serviceAccountRef:
      name: external-secrets-operator
      namespace: external-secrets 
```
Assuming  you’ve stored your database credentials in AWS Secrets Manager — for example:

database-secret contains the key DB_USERNAME and DB_PASSWORD

## Step 6: Create a Kubernetes ExternalSecret (external-secret.yaml):
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: external-secrets
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: aws-secret-store
    kind: ClusterSecretStore
  target:
    name: database-credentials
    creationPolicy: Owner
  data:
    - secretKey: DB_USERNAME
      remoteRef:
        key: database-secret
        property: DB_USERNAME
    - secretKey: DB_PASSWORD
      remoteRef:
        key: database-secret
        property: DB_PASSWORD
```
Save this as external-secret.yaml, then apply it

```bash
kubectl apply -f external-secret.yaml
```
### Verify the ExternalSecret:
```bash
kubectl get externalsecret database-credentials -n external-secrets
``` 
## Test using demo.yaml
```bash
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: external-secrets
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
        - name: web
          image: nginx:alpine
          env:
            - name: DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: database-credentials
                  key: DB_USERNAME
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: database-credentials
                  key: DB_PASSWORD
```                  
Apply the demo.yaml
```bash
kubectl apply -f demo.yaml
```





                    
