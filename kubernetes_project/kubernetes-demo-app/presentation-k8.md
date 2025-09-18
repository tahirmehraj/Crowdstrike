# SRE Technical Assessment
## Cloud-Native System Design & Operations

**Flask API on Amazon EKS - Practical Implementation**

---

## Slide 1: What I Built

**Delivered Components**:
- Flask API with health endpoints and metrics
- Production-ready Kubernetes deployment on EKS
- Terraform infrastructure for EKS cluster
- Comprehensive documentation and architecture analysis

**Working Endpoints**:
- `/` - API information with uptime
- `/hello` - Business endpoint with pod metadata
- `/healthz` - Liveness probe (used by Kubernetes)  
- `/readiness` - Readiness probe with minimum uptime check
- `/metrics` - Prometheus format metrics

**Live Demo Available**: All components working and deployable

---

## Slide 2: Architecture - What Actually Exists

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Internet  │────│ AWS Network  │────│   EKS Cluster   │
│   Traffic   │    │Load Balancer │    │   (Terraform)   │
└─────────────┘    └──────────────┘    └─────────────────┘
                           │                      │
                    Port 80 → 5000        ┌──────┴──────┐
                                         │ 3x Flask Pods │
                                         │ (deployment.yaml) │
                                         └───────────────┘
```

**Terraform Creates**:
- EKS cluster with managed control plane
- Managed node group (2-4 t3.medium instances)
- Security group with minimal access rules
- Kubeconfig file for cluster access

**Prerequisites** (Manual setup required):
- Existing VPC with private subnets
- IAM roles for cluster and node group
- Container registry for application image

---

## Slide 3: Flask Application - Production Features

**Health Check Implementation**:
```python
@app.route('/healthz')  # Kubernetes liveness probe
@app.route('/readiness') # Kubernetes readiness probe with 5s uptime requirement
```

**Observability Built-In**:
- **Structured logging**: JSON format with correlation IDs on every request
- **Request tracking**: Duration timing in middleware 
- **System metrics**: CPU, memory usage via psutil
- **Environment awareness**: Pod name, node, namespace injection

**Operational Features**:
- **Graceful shutdown**: SIGTERM handling with readiness state change
- **Error handling**: Structured error responses with correlation IDs
- **Security**: Runs as non-root user (UID 1000)

**Metrics Exposed** (actual implementation):
```
demo_app_uptime_seconds, demo_app_host_cpu_percent
demo_app_host_memory_percent, demo_app_ready
demo_app_info{version,environment,pod,node}
```

---

## Slide 4: Kubernetes Configuration - Real Implementation

**Deployment Strategy**:
```yaml
replicas: 3
strategy:
  rollingUpdate:
    maxUnavailable: 1  # Never below 2 replicas during updates
    maxSurge: 1       # Max 4 replicas during updates
```

**Resource Management**:
```yaml
resources:
  requests: { cpu: "50m", memory: "64Mi" }
  limits:   { cpu: "200m", memory: "128Mi" }
```

**Health Probes** (actual configuration):
- **Liveness**: `/healthz` every 10s, 3 failures = restart
- **Readiness**: `/readiness` every 5s, 2 failures = remove from traffic  
- **Startup**: 30s maximum startup time with extended failure tolerance

**HPA Configuration**:
- Scale between 2-10 pods
- CPU threshold: 70%, Memory threshold: 60%
- One-command metrics-server installation: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`

---

## Slide 5: Security Implementation

**Container Security**:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop: ["ALL"]  # Remove all Linux capabilities
```

**Network Security**:
- Private subnets for worker nodes
- Security group with self-referencing rules only
- EKS API endpoint configurable (currently public)

**Current Limitations**:
- Public EKS endpoint (can be restricted by CIDR)
- LoadBalancer type creates internet-facing NLB
- No network policies implemented
- Basic RBAC (EKS defaults)

---

## Slide 6: Infrastructure as Code - Actual Terraform

**What My Terraform Does**:
```hcl
# Creates 4 core resources:
resource "aws_eks_cluster"
resource "aws_eks_node_group"  
resource "aws_security_group"
resource "local_file" # kubeconfig generation
```

**Design Philosophy**:
- Uses existing VPC and subnets (enterprise pattern)
- Uses existing IAM roles (security team managed)
- Focuses on EKS-specific resources only
- Generates working kubeconfig for immediate access

**Deployment Process**:
1. `terraform apply` (creates EKS infrastructure)
2. `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
3. `kubectl apply` (deploys application)
4. AWS automatically provisions Network Load Balancer

---

## Slide 7: Operational Capabilities

**What Works Today**:
- **Health monitoring**: Kubernetes probes functional
- **Auto-scaling**: HPA works once metrics-server installed
- **Load balancing**: AWS NLB distributes traffic
- **Logging**: `kubectl logs` provides structured application logs

**Monitoring Available**:
- `kubectl get pods` - pod health status
- `kubectl top pods` - resource utilization (requires metrics-server)
- `kubectl describe hpa` - scaling decisions and metrics
- Application `/metrics` endpoint - custom application metrics

**Troubleshooting Commands** (documented):
```bash
kubectl logs -l app=demo-api --tail=50
kubectl describe pods -l app=demo-api  
kubectl get events --sort-by=.metadata.creationTimestamp
```

---

## Slide 8: Cost Analysis

**Monthly Cost Estimate**:
- **EKS Control Plane**: $72 (fixed AWS charge)
- **Worker Nodes**: $60-120 (2-4 t3.medium instances)
- **Network Load Balancer**: $16-22 (AWS NLB pricing)
- **Total**: Approximately $150-215/month

**Cost Controls Implemented**:
- Resource limits prevent pod resource exhaustion
- HPA scaling boundaries (2-10 pods) control maximum cost
- Node group auto-scaling (2-4 nodes) matches demand
- t3.medium instance type balances cost and performance

**Missing Cost Optimizations**:
- No spot instances configured
- No scheduled scaling for predictable workloads
- Could use ingress controller instead of LoadBalancer for cost savings

---

## Slide 9: Documentation & Knowledge Transfer

**Delivered Documentation**:
- **README.md**: Complete setup instructions with actual prerequisites
- **architecture.md**: System design and component interactions
- **Terraform variables**: All configurable parameters documented
- **Kubernetes manifests**: Extensive comments explaining each choice

**Key Technical Decisions Documented**:
- Why existing VPC/IAM approach vs full infrastructure creation
- Health check timing and failure thresholds
- Resource limits and HPA scaling parameters
- Security context and container hardening choices

**Setup Verification**:
- All code tested and deployable
- Container image builds successfully
- Terraform creates working cluster
- Application responds to all endpoints

---

## Slide 10: Current State & Interview Demo

**What I Can Demonstrate Live**:
- **Terraform deployment**: EKS cluster creation from scratch
- **Application deployment**: Pod startup and health check progression
- **Health endpoints**: All endpoints responding with proper data
- **Scaling behavior**: Manual scaling demonstration
- **Failure simulation**: Pod deletion and automatic restart

**Current Limitations** (honest assessment):
- No Prometheus server deployed (metrics endpoint exists, no collection)
- No alerting system (thresholds documented, not implemented)
- No CI/CD pipeline (manual deployment process)
- Simple metrics-server installation required (one kubectl command)
- Container image must be pushed to accessible registry

**Next Steps for Production**:
- Deploy monitoring stack (Prometheus + Grafana)
- Implement automated CI/CD pipeline  
- Add ingress controller to reduce LoadBalancer costs
- Enhance security with network policies and private endpoints
