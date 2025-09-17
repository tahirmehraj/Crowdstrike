# System Architecture
## Kubernetes Demo API - SRE Technical Assessment

### Overview
Flask API on Amazon EKS demonstrating cloud-native SRE practices with auto-scaling, health checks, and comprehensive observability.

--- 

## Core Components

### Infrastructure (Terraform)
- **EKS Cluster**: Kubernetes 1.28, multi-AZ deployment
- **Node Group**: 2-6 t3.medium instances, auto-scaling enabled
- **Networking**: Existing VPC with private subnets across 3 AZs
- **Security**: Minimal security group, IAM roles with least privilege

### Application (Kubernetes)
```yaml
Deployment:
  - Replicas: 3 (high availability)
  - Rolling updates: maxUnavailable=1, maxSurge=1
  - Resources: 50m CPU / 64Mi RAM → 200m CPU / 128Mi RAM
  - Security: non-root user, dropped capabilities

Service:
  - Type: ClusterIP
  - Load balancing: Round-robin across healthy pods
  - Port: 80 → 5000

HPA:
  - Scale: 2-10 pods based on CPU (70%) & memory (80%)
  - Behavior: Aggressive scale-up, conservative scale-down
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
  - Structured logging with JSON format
  - System metrics (CPU, memory via psutil)
  - Graceful error handling
  - Environment-aware configuration
```

---

## Data Flow

### Request Flow
```
Client → Service (ClusterIP) → Pod (Flask API) → Response
         ↓
    Load balances across 3 healthy pods
```

### Auto-Scaling Flow
```
Pod Metrics → HPA → Scaling Decision → Deployment → New/Removed Pods
```

### Health Check Flow
```
kubelet → Liveness Probe (GET /healthz every 10s) → Pod restart if failed
kubelet → Readiness Probe (GET /readiness every 5s) → Traffic routing
```

---

## Security Model

### Network Security
- **VPC**: Private subnets with NAT gateway egress
- **Security Group**: Self-referencing rules only
- **EKS**: Managed control plane with AWS security

### Container Security
- **User**: Non-root execution (UID 1000)
- **Capabilities**: All Linux capabilities dropped
- **Resources**: Memory/CPU limits prevent DoS attacks
- **Image**: Multi-stage build, minimal attack surface

---

## Observability

### Metrics (Prometheus format)
```
demo_app_uptime_seconds          # Application uptime
demo_app_cpu_usage_percent       # System CPU utilization  
demo_app_memory_usage_percent    # System memory usage
demo_app_ready                   # Readiness state (1/0)
demo_app_info{version,env}       # Application metadata
```

### Health Monitoring
- **Startup**: 10s delay, 5s interval, 6 failures = 30s max startup
- **Liveness**: 30s delay, 10s interval, 3 failures = pod restart  
- **Readiness**: 5s delay, 5s interval, 2 failures = traffic removal

### Logging
- Structured JSON logs to stdout
- Kubernetes log aggregation via `kubectl logs`
- Request/response logging with correlation IDs

---

## Scaling Strategy

### Horizontal Scaling (HPA)
```
Triggers:
  CPU > 70% → Scale up (aggressive, 100% increase)
  Memory > 80% → Scale up
  Load decrease → Scale down (conservative, 10% reduction)

Boundaries:
  Min: 2 pods (HA requirement)
  Max: 10 pods (cost control)
  Stabilization: 60s up, 300s down
```

### Infrastructure Scaling
```
Node Group Auto-scaling:
  Min: 2 nodes
  Max: 6 nodes  
  Instance: t3.medium
  Trigger: Pod scheduling pressure
```

---

## Failure Handling

### Pod-Level
- **Health check failure**: Automatic restart via liveness probe
- **Traffic readiness**: Removed from service until ready
- **Resource limits**: OOMKill protection with graceful restart

### Node-Level  
- **Node failure**: Pods rescheduled to healthy nodes
- **AZ failure**: Multi-AZ deployment maintains availability
- **Capacity**: Auto-scaling adds nodes when needed

### Application-Level
- **Startup grace period**: 30s for initialization
- **Graceful shutdown**: 30s termination grace period
- **Error responses**: Proper HTTP status codes with structured errors

---

## Cost Model

### Current Costs (Monthly)
- **EKS Control Plane**: $72 (fixed)
- **EC2 Instances**: $60-180 (2-6 t3.medium nodes)  
- **Storage**: $10 (EBS volumes)
- **Networking**: Minimal (internal traffic)
- **Total**: ~$145-265/month

### Cost Optimization
- **HPA**: Dynamic scaling reduces over-provisioning
- **Resource limits**: Prevents waste
- **Spot instances**: Architecture supports spot nodes
- **Right-sizing**: Regular utilization review

---

## Key SRE Principles Demonstrated

**Reliability**: Multi-AZ deployment, health checks, auto-scaling
**Observability**: Metrics, logging, health endpoints, monitoring-ready
**Security**: Defense in depth, least privilege, container hardening  
**Scalability**: Horizontal/vertical scaling, resource management
**Automation**: Infrastructure as code, self-healing via probes
**Cost Management**: Resource limits, dynamic scaling, optimization

---

## Files Structure
```
terraform/
├── main.tf              # EKS cluster and node group
├── variables.tf         # Input parameters  
├── outputs.tf           # Cluster connection info
├── terraform.tfvars     # Environment-specific values
└── kubeconfig.tpl       # kubectl access template

kubernetes/
├── deployment.yaml      # Application deployment with HPA
├── service.yaml         # Load balancer service
└── hpa.yaml            # Horizontal pod autoscaler

application/
├── app.py              # Flask API with health endpoints
├── Dockerfile          # Multi-stage container build
├── requirements.txt    # Python dependencies
└── README.md          # Setup and operations guide
```