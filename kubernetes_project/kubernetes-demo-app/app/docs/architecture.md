# System Architecture - Actual Implementation
## Kubernetes Demo API - SRE Technical Assessment

### Overview
Flask API deployed on Amazon EKS demonstrating SRE practices with auto-scaling, health checks, and basic observability. Uses existing AWS infrastructure components.

---

## Core Components

### Infrastructure (Terraform - Simplified)
- **EKS Cluster**: Basic managed Kubernetes control plane
- **Managed Node Group**: 2-4 t3.medium instances with auto-scaling
- **Networking**: Uses existing VPC and private subnets
- **Security**: Basic security group with self-referencing rules
- **IAM**: Uses existing cluster and node group roles (created manually)

### Application (Kubernetes)
```yaml
Deployment:
  - Replicas: 3 (high availability)
  - Rolling updates: maxUnavailable=1, maxSurge=1
  - Resources: 50m CPU / 64Mi RAM → 200m CPU / 128Mi RAM
  - Security: non-root user, dropped capabilities

Service:
  - Type: LoadBalancer (AWS Network Load Balancer)
  - External access: Internet-facing NLB
  - Port: 80 → 5000

HPA:
  - Scale: 2-10 pods based on CPU (70%) & memory (60%)
  - Requires manual metrics-server installation
```

### Flask Application
```python
Endpoints:
  /           # API information
  /hello      # Greeting with metadata  
  /healthz    # Liveness probe
  /readiness  # Readiness probe (5s min uptime)
  /metrics    # Prometheus metrics

Features:
  - Structured logging with correlation IDs
  - System metrics (CPU, memory via psutil)
  - Graceful shutdown handling
  - Pod metadata injection
```

---

## Actual Data Flow

### Request Flow
```
Internet → AWS NLB → Pod (Flask API) → Response
           ↓
    Load balances across healthy pods in existing VPC
```

### Infrastructure Dependencies
```
Manual Prerequisites:
  - VPC with private subnets
  - NAT gateway for internet access
  - EKS cluster IAM role with AmazonEKSClusterPolicy
  - Node group IAM role with worker policies

Terraform Creates:
  - EKS cluster resource
  - Managed node group
  - Basic security group
  - Kubeconfig file
```

### Scaling Dependencies
```
Simple Installation:
  - metrics-server: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  
Kubernetes Native:
  - HPA reads metrics-server data
  - Scales deployment replicas
  - Node group auto-scaling handles capacity
```

---

## Security Implementation

### Network Security
- **Existing VPC**: Uses customer-provided private subnets
- **Security Group**: Self-referencing traffic only
- **EKS API**: Public endpoint (configurable)
- **Worker Nodes**: Private subnets with NAT gateway egress

### IAM Security
- **Cluster Role**: Manually created with minimal EKS permissions
- **Node Role**: Manually created with worker node policies
- **RBAC**: Uses EKS default service account permissions

### Container Security
- **User**: Non-root execution (UID 1000)
- **Capabilities**: All Linux capabilities dropped
- **Resources**: Strict memory/CPU limits
- **Registry**: Customer-provided container registry

---

## Observability - Current State

### Metrics Available
```
# Application metrics from /metrics endpoint
demo_app_uptime_seconds
demo_app_host_cpu_percent  
demo_app_host_memory_percent
demo_app_host_memory_bytes
demo_app_ready
demo_app_info{version,env,pod,node}

# Kubernetes native metrics (requires metrics-server)
kubectl top nodes
kubectl top pods
```

### Health Monitoring
- **Liveness**: HTTP GET /healthz every 10s
- **Readiness**: HTTP GET /readiness every 5s  
- **Startup**: HTTP GET /healthz with extended failure tolerance
- **Logging**: Structured JSON to stdout → `kubectl logs`

### Limitations
- **No Prometheus server**: Metrics endpoint exists but no collection
- **No Grafana dashboards**: Visualization not implemented
- **No alerting**: No alert manager or notification setup
- **Basic monitoring**: Relies on `kubectl` commands for troubleshooting

---

## Cost Model - Actual Implementation

### Monthly Costs
- **EKS Control Plane**: $72 (fixed)
- **EC2 Instances**: 
  - 2 t3.medium: ~$60/month (minimum)
  - 4 t3.medium: ~$120/month (maximum)
- **Network Load Balancer**: ~$16-22/month
- **Data Transfer**: Variable based on usage
- **Storage**: Minimal EBS costs
- **Total**: ~$150-215/month

### Cost Dependencies
- **VPC/NAT**: Customer responsibility (existing infrastructure)
- **Container Registry**: Customer choice (ECR, DockerHub, etc.)
- **Monitoring**: None deployed (additional cost if added)

---

## Operational Readiness

### What Works Out of Box
- **Application deployment**: All manifests ready
- **Health checks**: Comprehensive probe configuration
- **Auto-scaling**: HPA functional once metrics-server installed
- **Load balancing**: AWS NLB handles traffic distribution
- **Security**: Container and network hardening applied

### Manual Setup Required
- **Infrastructure prerequisites**: VPC, subnets, IAM roles
- **Metrics server**: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
- **Container registry**: Build and push demo-api image
- **kubectl configuration**: Use generated kubeconfig file
- **Monitoring stack**: No automated deployment

### Operational Commands
```bash
# Deployment
terraform apply
kubectl apply -f deployment.yaml -f service.yaml -f hpa.yaml

# Verification  
kubectl get pods -l app=demo-api
kubectl get svc demo-api-service
kubectl describe hpa demo-api-hpa

# Troubleshooting
kubectl logs -l app=demo-api --tail=50
kubectl describe pods -l app=demo-api
kubectl top pods -l app=demo-api
```

---

## Terraform Architecture Pattern

### Resource Creation Strategy
```hcl
# What Terraform Creates
├── aws_eks_cluster (control plane)
├── aws_eks_node_group (worker nodes)  
├── aws_security_group (cluster networking)
└── local_file (kubeconfig)

# What Must Exist (Prerequisites)
├── VPC and subnets (customer provided)
├── IAM cluster role (customer created)
├── IAM node group role (customer created)
└── Container registry (customer choice)
```

### Integration Points
- **AWS CLI**: Used for EKS authentication in kubeconfig
- **kubectl**: Generated config connects to cluster
- **Container Runtime**: EKS manages Docker/containerd
- **AWS Load Balancer Controller**: Auto-provisioned for LoadBalancer services

---

## SRE Principles Demonstrated

**Reliability**: Health checks, multi-replica deployment, auto-scaling
**Simplicity**: Minimal infrastructure, existing resource reuse  
**Observability**: Metrics endpoints, structured logging, health probes
**Security**: Container hardening, network isolation, IAM integration
**Automation**: Infrastructure as code, rolling deployments
**Cost Awareness**: Resource limits, instance type selection, auto-scaling boundaries

---

## Current Limitations & Trade-offs

### Simplifications Made
- **No VPC creation**: Assumes existing network infrastructure
- **Manual IAM setup**: Avoids complex permission management in Terraform
- **Basic monitoring**: Metrics endpoints without collection infrastructure
- **Single region**: No multi-region redundancy
- **Manual metrics-server**: Not automated in Terraform deployment

### Production Enhancements Needed
- **Monitoring stack**: Prometheus, Grafana, AlertManager
- **Ingress controller**: Replace LoadBalancer with ingress for cost optimization
- **GitOps**: CI/CD pipeline for automated deployments
- **Backup strategy**: Persistent volume and configuration backup
- **Multi-environment**: Separate dev/staging/prod configurations