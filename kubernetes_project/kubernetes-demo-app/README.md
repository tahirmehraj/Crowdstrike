# Kubernetes Demo Application

## Overview

This project demonstrates SRE best practices for deploying containerized applications on Kubernetes. It includes:

- **Simple Flask API** with health checks and metrics endpoints
- **Production-ready EKS cluster** provisioned via Terraform
- **Kubernetes manifests** with reliability features (probes, HPA, resource limits)
- **Auto-scaling** based on CPU and memory utilization
- **Observability** with Prometheus metrics and structured logging

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Internet      │    │  Load Balancer  │    │   EKS Cluster   │
│   Traffic       │───▶│     (ALB)       │───▶│                 │
└─────────────────┘    └─────────────────┘    │  ┌─────────────┐ │
                                              │  │ Demo API    │ │
                                              │  │ Pods (2-10) │ │
                                              │  └─────────────┘ │
                                              │                 │
                                              │  ┌─────────────┐ │
                                              │  │   HPA       │ │
                                              │  │ Autoscaler  │ │
                                              │  └─────────────┘ │
                                              └─────────────────┘
```

## Project Structure

```
kubernetes-demo-app/
├── app/                     # Flask application
│   ├── app.py              # Main application with endpoints
│   ├── Dockerfile          # Container image definition
│   └── requirements.txt    # Python dependencies
├── k8s-manifests/          # Kubernetes deployment files
│   ├── deployment.yaml     # Pod deployment with probes
│   ├── service.yaml        # Load balancer service
│   └── hpa.yaml           # Horizontal Pod Autoscaler
├── terraform/              # EKS infrastructure
│   ├── main.tf            # EKS cluster and VPC
│   ├── variables.tf       # Configuration variables
│   ├── outputs.tf         # Cluster connection info
│   └── terraform.tfvars.example
└── README.md              # This file
```

## API Endpoints

The Flask application provides the following endpoints:

- **`GET /`** - API information and available endpoints
- **`GET /hello`** - Simple greeting endpoint for testing
- **`GET /healthz`** - Liveness probe for Kubernetes
- **`GET /readiness`** - Readiness probe for Kubernetes
- **`GET /metrics`** - Prometheus metrics for monitoring

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Docker (for building container images)
- kubectl (for interacting with Kubernetes)

### 1. Deploy EKS Cluster

```bash
# Navigate to terraform directory
cd terraform/

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred settings

# Initialize and deploy infrastructure
terraform init
terraform plan
terraform apply

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name demo-app-cluster-dev
```

### 2. Build and Push Container Image

```bash
# Navigate to app directory
cd app/

# Build the Docker image
docker build -t demo-api:latest .

# Tag and push to ECR (replace with your ECR URI)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
docker tag demo-api:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/demo-api:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/demo-api:latest
```

### 3. Deploy Application

```bash
# Update image in deployment.yaml
# Replace "demo-api:latest" with your ECR image URI

# Deploy to Kubernetes
kubectl apply -f k8s-manifests/

# Verify deployment
kubectl get pods -l app=demo-api
kubectl get services
kubectl get hpa
```

### 4. Access Application

```bash
# Get load balancer URL
kubectl get service demo-api-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test endpoints
curl http://<load-balancer-url>/hello
curl http://<load-balancer-url>/healthz
curl http://<load-balancer-url>/metrics
```

## SRE Features Demonstrated

### 1. Health Checks and Self-Healing

```yaml
# Liveness probe - restarts unhealthy pods
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

# Readiness probe - controls traffic routing
readinessProbe:
  httpGet:
    path: /readiness
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 2
```

### 2. Auto-Scaling

```yaml
# HPA scales based on CPU/memory utilization
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70
```

### 3. Resource Management

```yaml
# Resource limits prevent resource starvation
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "200m"
```

### 4. Observability

- **Structured logging** for debugging
- **Prometheus metrics** for monitoring
- **Health check endpoints** for status verification
- **Pod labels and annotations** for service discovery

## Monitoring and Troubleshooting

### Check Application Status

```bash
# View pod status
kubectl get pods -l app=demo-api

# Check pod logs
kubectl logs -l app=demo-api --tail=50

# Describe deployment
kubectl describe deployment demo-api

# Check HPA status
kubectl get hpa
kubectl describe hpa demo-api-hpa
```

### Load Testing (Trigger Auto-Scaling)

```bash
# Create a temporary pod for load testing
kubectl run load-test --image=busybox --rm -it -- /bin/sh

# Inside the pod, generate load
while true; do wget -q -O- http://demo-api-service:5000/hello; done
```

### View Metrics

```bash
# Port forward to access metrics locally
kubectl port-forward service/demo-api-internal 5000:5000

# View metrics in browser
curl http://localhost:5000/metrics
```

## Configuration Options

### Environment Variables

The application supports these environment variables:

- `ENVIRONMENT` - Application environment (development, kubernetes, production)
- `PORT` - Server port (default: 5000)
- `DEBUG` - Enable debug mode (true/false)

### Terraform Variables

Key configuration options in `terraform.tfvars`:

- `aws_region` - AWS region for deployment
- `environment` - Environment name (dev, staging, prod)
- `node_instance_types` - EC2 instance types for worker nodes
- `node_group_min_size` - Minimum number of worker nodes
- `node_group_max_size` - Maximum number of worker nodes

## Cost Optimization

### Development Environment

```bash
# Use smaller instances and single NAT gateway
node_instance_types = ["t3.small"]
single_nat_gateway = true
node_group_min_size = 1
node_group_desired_size = 1
```

### Production Environment

```bash
# Use larger instances and multiple NAT gateways for HA
node_instance_types = ["t3.large"]
single_nat_gateway = false
node_group_min_size = 3
node_group_desired_size = 3
```

## Security Best Practices

### Container Security

- **Non-root user** in container
- **Read-only root filesystem** where possible
- **Dropped Linux capabilities**
- **Resource limits** to prevent abuse

### Kubernetes Security

- **Network policies** for traffic control
- **RBAC** for access control
- **Pod security standards** enforcement
- **Secrets management** for sensitive data

### Infrastructure Security

- **Private subnets** for worker nodes
- **Security groups** with least privilege
- **VPC endpoints** for AWS service access
- **Encryption** for data at rest and in transit

## Cleanup

```bash
# Delete Kubernetes resources
kubectl delete -f k8s-manifests/

# Destroy infrastructure
cd terraform/
terraform destroy
```

## Next Steps

## Troubleshooting

### Common Issues

1. **Pod stuck in Pending**
   - Check node capacity: `kubectl describe nodes`
   - Verify resource requests vs available resources

2. **Load balancer not accessible**
   - Check security groups allow inbound traffic
   - Verify AWS Load Balancer Controller is running

3. **HPA not scaling**
   - Ensure metrics server is installed: `kubectl get deployment metrics-server -n kube-system`
   - Check resource requests are defined in deployment

4. **Container image pull errors**
   - Verify ECR permissions
   - Check image URI in deployment.yaml

