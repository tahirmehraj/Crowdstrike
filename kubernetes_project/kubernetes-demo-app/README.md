# Kubernetes Demo API
**SRE Technical Assessment - Flask API on EKS**

## Overview
Containerized Flask API deployed on Amazon EKS demonstrating SRE best practices including auto-scaling, health checks, monitoring, and infrastructure as code.

**Endpoints:**
- `/` - API info
- `/hello` - Simple greeting  
- `/healthz` - Liveness probe
- `/readiness` - Readiness probe
- `/metrics` - Prometheus metrics

## Prerequisites
- AWS CLI configured with EKS permissions
- Terraform 1.2.0+
- kubectl
- Docker
- Existing VPC, subnets, and IAM roles (see `terraform.tfvars.example`)

## Quick Deployment

### 1. Infrastructure
```bash
# Configure Terraform variables
cp terraform.tfvars.example terraform.tfvars
# Edit with your VPC ID, subnet IDs, and IAM role ARNs

# Deploy EKS cluster
terraform init && terraform apply

# Configure kubectl
export KUBECONFIG=$(pwd)/kubeconfig_demo-eks-cluster
kubectl get nodes
```

### 2. Application
```bash
# Build and push container
docker build -t demo-api:v1.0.0 .
docker tag demo-api:v1.0.0 YOUR_REGISTRY/demo-api:v1.0.0
docker push YOUR_REGISTRY/demo-api:v1.0.0

# Update image in deployment.yaml, then deploy
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml  
kubectl apply -f hpa.yaml
```

### 3. Verify
```bash
kubectl get pods -l app=demo-api
kubectl port-forward svc/demo-api-service 8080:80
curl http://localhost:8080/hello
```

## Configuration

**Key Terraform Variables:**
```hcl
cluster_name       = "demo-eks-cluster"
vpc_id            = "vpc-xxxxx" 
subnet_ids        = ["subnet-a", "subnet-b", "subnet-c"]
cluster_role_arn  = "arn:aws:iam::account:role/eks-cluster-role"
node_group_role_arn = "arn:aws:iam::account:role/eks-nodegroup-role"
```

**Kubernetes Features:**
- 3 replicas with rolling updates
- HPA: 2-10 pods based on CPU (70%) and memory (80%)
- Health/readiness probes with proper timing
- Resource limits: 128Mi memory, 200m CPU
- Security: non-root user, dropped capabilities

## Monitoring
```bash
# Check application health
kubectl get pods -l app=demo-api
kubectl top pods -l app=demo-api

# View metrics
kubectl port-forward svc/demo-api-service 8080:80
curl http://localhost:8080/metrics

# Check HPA scaling
kubectl get hpa demo-api-hpa
```

## Common Operations

**Scaling:**
```bash
kubectl scale deployment demo-api --replicas=5
kubectl get hpa demo-api-hpa
```

**Updates:**
```bash
kubectl set image deployment/demo-api demo-api=new-image:tag
kubectl rollout status deployment/demo-api
kubectl rollout undo deployment/demo-api  # if needed
```

**Troubleshooting:**
```bash
kubectl describe pods -l app=demo-api
kubectl logs -l app=demo-api --tail=50
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Security Features
- Container runs as non-root user (UID 1000)
- Security contexts with dropped capabilities
- Resource limits prevent resource exhaustion
- Network security groups with minimal required access

## Architecture
```
AWS EKS Cluster
├── Node Group (t3.medium, 2-6 nodes)
├── Demo API Deployment (3 replicas)
│   ├── Flask app with health endpoints
│   ├── Prometheus metrics exposure
│   └── Auto-scaling via HPA
├── Service (ClusterIP with load balancing)
└── Monitoring integration ready
```

## Files
- `main.tf` - EKS cluster and node group
- `deployment.yaml` - Application deployment with HPA
- `service.yaml` - Load balancer service  
- `app.py` - Flask API with health checks
- `Dockerfile` - Multi-stage container build
- `requirements.txt` - Python dependencies

## Cost Optimization
- t3.medium instances (2-6 nodes): ~$60-180/month
- EKS control plane: $72/month
- Use spot instances and cluster autoscaler for production

