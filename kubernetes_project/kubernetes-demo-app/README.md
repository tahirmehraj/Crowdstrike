# Kubernetes Demo API
**SRE Technical Assessment - Flask API on EKS**

## Prerequisites
- AWS CLI configured with EKS permissions
- Terraform 1.2.0+
- kubectl
- Docker
- **Existing VPC, subnets, and IAM roles (must be created manually)**

## Infrastructure Setup - IMPORTANT

### **Pre-requisites (Manual Setup Required)**

Before running Terraform, you must manually create:

1. **VPC and Subnets**: 
   - 1 VPC with internet gateway
   - At least 2 private subnets across different AZs
   - NAT gateway for private subnet internet access

2. **IAM Roles**:
   - EKS Cluster Service Role with policies:
     - `AmazonEKSClusterPolicy`
   - EKS Node Group Role with policies:
     - `AmazonEKSWorkerNodePolicy`
     - `AmazonEKS_CNI_Policy`  
     - `AmazonEC2ContainerRegistryReadOnly`

### **1. Infrastructure Deployment**

```bash
# Configure Terraform variables
cp terraform.tfvars.example terraform.tfvars

# EDIT terraform.tfvars with your actual values:
# - vpc_id: Your existing VPC ID
# - subnet_ids: Your existing private subnet IDs  
# - cluster_role_arn: Your EKS cluster IAM role ARN
# - node_group_role_arn: Your EKS node group IAM role ARN

# Deploy EKS cluster
terraform init
terraform plan
terraform apply

# Configure kubectl
export KUBECONFIG=$(pwd)/kubeconfig_demo-eks-cluster
kubectl get nodes
```

### **2. Install Metrics Server (Required for HPA)**

```bash
# Install metrics server for HPA functionality
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify installation
kubectl get deployment metrics-server -n kube-system
kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system

# Test metrics collection (should show CPU/memory usage)
kubectl top nodes
kubectl top pods -l app=demo-api
```

### **3. Application Deployment**

```bash
# Build and push container to your registry
docker build -t demo-api:v1.0.0 .
docker tag demo-api:v1.0.0 YOUR_REGISTRY/demo-api:v1.0.0
docker push YOUR_REGISTRY/demo-api:v1.0.0

# Update deployment.yaml with your registry URL
sed -i 's|demo-api:latest|YOUR_REGISTRY/demo-api:v1.0.0|' deployment.yaml

# Deploy application
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml  
kubectl apply -f hpa.yaml
```

### **4. Verification**

```bash
# Wait for LoadBalancer provisioning (2-5 minutes)
kubectl get svc demo-api-service -w

# Get external IP and test
EXTERNAL_IP=$(kubectl get svc demo-api-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$EXTERNAL_IP/hello
```

## Configuration

**Key Terraform Variables (terraform.tfvars):**
```hcl
# Infrastructure (must exist already)
vpc_id            = "vpc-xxxxx" 
subnet_ids        = ["subnet-a", "subnet-b", "subnet-c"]
cluster_role_arn  = "arn:aws:iam::account:role/eks-cluster-role"
node_group_role_arn = "arn:aws:iam::account:role/eks-nodegroup-role"

# Cluster configuration
cluster_name    = "demo-eks-cluster"
cluster_version = "1.28"
node_instance_type = "t3.medium"
node_desired    = 2
node_min        = 2  
node_max        = 4
```

## Terraform Outputs

After successful deployment, Terraform provides:
- **cluster_name**: EKS cluster name
- **cluster_endpoint**: Kubernetes API endpoint
- **node_group_name**: Managed node group name
- **kubeconfig_file**: Path to generated kubectl config

## Architecture Limitations

**Current Terraform Implementation:**
- Uses existing VPC/subnets (no VPC creation)
- Uses existing IAM roles (no IAM resource creation)
- Basic EKS cluster without advanced addons
- Manual metrics server installation required
- No automated monitoring stack deployment

**Manual Prerequisites Required:**
- VPC with proper subnet configuration
- IAM roles with correct policies attached
- Container registry for image storage
- DNS/networking properly configured

## Files Structure
```
project-root/
├── main.tf                    # Core EKS cluster and node group
├── variables.tf               # Input parameters  
├── outputs.tf                 # Connection information
├── kubeconfig.tpl            # kubectl configuration template
├── terraform.tfvars.example  # Example configuration
├── deployment.yaml           # Application deployment
├── service.yaml              # LoadBalancer service
└── hpa.yaml                 # Horizontal pod autoscaler
```

## Cost Optimization
- EKS control plane: $72/month
- t3.medium instances (2-4 nodes): ~$60-120/month  
- **AWS Network Load Balancer**: ~$16-22/month
- **Total**: ~$150-215/month

## Security Notes
- **IAM**: Least privilege roles (created manually)
- **Network**: Uses existing VPC security configuration  
- **Container**: Non-root user, dropped capabilities
- **API**: Public endpoint (restrict in production)

## Troubleshooting

**Common Issues:**
1. **Missing IAM permissions**: Ensure roles have correct policies
2. **VPC/subnet configuration**: Subnets must have internet access via NAT
3. **Metrics server**: Must be installed manually for HPA to work
4. **Container image**: Must be pushed to accessible registry