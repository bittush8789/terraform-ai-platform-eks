# Amazon EKS Cluster Using Terraform

This repository provisions a beginner-friendly, secure, and production-ready **Amazon Elastic Kubernetes Service (EKS)** cluster on AWS using Terraform from scratch. Additionally, it implements a comprehensive cluster monitoring suite using Kubernetes Metrics Server, Prometheus, and Grafana deployed via Helm.

---

## Architecture Diagram

```text
                    Internet
                        │
                        ▼
                Internet Gateway
                        │
                        ▼
                      VPC (10.0.0.0/16)
          ┌─────────────┴─────────────┐
          ▼                           ▼
   Public Subnets (ap-south-1a/b)     Private Subnets (ap-south-1a/b)
   [10.0.1.0/24, 10.0.2.0/24]         [10.0.10.0/24, 10.0.20.0/24]
          │                           │
          ▼                           ▼
     NAT Gateway                  EKS Cluster Control Plane (1.30)
                                      │
                                      ▼
                                Managed Nodes (t3.medium)
                                      │
                                      ▼
                                Kubernetes Pods (Nginx / Monitoring)
```

---

## Directory Structure

```text
terraform-eks/
├── provider.tf        # Dynamic provider setup for AWS, Kubernetes, and Helm
├── versions.tf        # Specifying Terraform and provider version constraints
├── variables.tf       # Parameter declaration (Region, VPC, Subnets, Node sizing, etc.)
├── terraform.tfvars   # Input values for customization (Mumbai region defaults)
├── main.tf            # Main configuration (VPC, IAM, Security Groups, EKS, Helm)
├── outputs.tf         # Generated outputs (Endpoints, ARNs, VPC IDs)
├── README.md          # Comprehensive usage and design documentation
└── .gitignore         # Prevents checking in state and secret files
```

---

## Architectural Details & Components

### 1. VPC Networking Components
*   **VPC (`10.0.0.0/16`)**: An isolated virtual network that contains all resources.
*   **Public Subnets (`10.0.1.0/24`, `10.0.2.0/24`)**: Subnets that map public IPs on launch. They host the NAT Gateway and public load balancers (`kubernetes.io/role/elb = 1`).
*   **Private Subnets (`10.0.10.0/24`, `10.0.20.0/24`)**: Isolated subnets where the worker nodes reside (`kubernetes.io/role/internal-elb = 1`). They do not accept direct incoming traffic from the internet, ensuring a secure runtime environment.
*   **Internet Gateway (IGW)**: Provides a gateway for public subnets to access and receive traffic from the internet.
*   **Elastic IP (EIP) & NAT Gateway**: The NAT Gateway sits in a public subnet and leverages an Elastic IP to allow resources in private subnets (like worker nodes and pods) to connect to the internet (for package updates and API requests) without revealing their private IP addresses.
*   **Route Tables & Associations**:
    *   *Public RT*: Forwards `0.0.0.0/0` to the Internet Gateway.
    *   *Private RT*: Forwards `0.0.0.0/0` to the NAT Gateway.

### 2. IAM Roles & Policies
*   **EKS Cluster Role (`AmazonEKSClusterPolicy`)**: Allows the EKS control plane to manage AWS resources (like Elastic Load Balancers, security groups, and network interfaces) on your behalf.
*   **Worker Nodes Role**:
    *   `AmazonEKSWorkerNodePolicy`: Grants the worker nodes permission to check in and register with the EKS cluster.
    *   `AmazonEKS_CNI_Policy`: Grants the VPC CNI plugin permission to manage Elastic Network Interfaces (ENIs) and allocate private IPs to pods.
    *   `AmazonEC2ContainerRegistryReadOnly`: Allows worker nodes to pull container images from private and public Amazon Elastic Container Registry (ECR).

### 3. Managed Node Group
*   **Instance Type**: `t3.medium` (2 vCPUs, 4 GiB Memory) is used to support standard application workloads and the monitoring stack.
*   **Scaling Bounds**: Minimum 1 node, desired 2 nodes, maximum 3 nodes. Sized dynamically based on resource usage.
*   **Operating System**: Amazon Linux 2023 (`AL2023_x86_64_STANDARD`) for enhanced performance, modern kernel features, and improved security defaults.
*   **Disk Size**: `20 GB` EBS volumes per node to host container images and local pod logging storage.

### 4. Security Group Configurations
*   **Least Privilege Approach**:
    *   Worker nodes are restricted from direct SSH/ingress.
    *   Only necessary control plane traffic is allowed (Port 443 for API communications and Port 10250 for Kubelet statistics).
    *   Unrestricted communication is permitted *within* the worker node security group so pods on different nodes can talk to one another directly.

---

## Deployment Instructions

Execute the following commands in the `terraform-eks` folder:

### 1. Initialize Working Directory
Downloads required providers (AWS, Kubernetes, Helm) and sets up local workspaces.
```bash
terraform init
```

### 2. Validate Code Syntax & Format
```bash
# Formats all terraform files to canonical standard formatting
terraform fmt

# Validates syntax and verifies configuration logic is correct
terraform validate
```

### 3. Review Plan
Generates a dry-run execution blueprint showing exactly what resources will be created.
```bash
terraform plan
```

### 4. Apply Infrastructure
Creates the VPC, subnets, IAM roles, EKS Cluster, node group, and monitoring Helm applications.
```bash
terraform apply -auto-approve
```
*Note: The creation process can take 15–20 minutes as AWS provisions the managed control plane and launches EC2 instances.*

---

## Kubernetes Validation Steps

### 1. Update local Kubeconfig
Configure your local `kubectl` context to securely connect to the new EKS cluster API.
```bash
aws eks update-kubeconfig --region ap-south-1 --name basic-eks-cluster
```

### 2. Verify Nodes
Verify that your EC2 worker nodes are registered, active, and running Amazon Linux 2023.
```bash
kubectl get nodes -o wide
```

### 3. Verify System & Monitoring Namespaces
```bash
kubectl get namespaces
```

### 4. Deploy and Expose Sample Application
Verify application deployment, ingress, and AWS LoadBalancer creation:
```bash
# Deploy Nginx
kubectl create deployment nginx --image=nginx

# Expose Nginx via an Elastic Load Balancer (ELB)
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# View Service details (wait a minute for the External IP DNS name to be created)
kubectl get svc nginx
```
Test access by copying the `EXTERNAL-IP` address into your web browser.

---

## Monitoring Validation (Bonus Challenge)

The monitoring infrastructure deploys **Metrics Server**, **Prometheus**, and **Grafana** automatically inside the `monitoring` namespace if `enable_monitoring = true`.

### 1. Check Metrics Server
Verify metrics are flowing for nodes and pods:
```bash
kubectl top nodes
kubectl top pods -n kube-system
```

### 2. Access Grafana Dashboard
Access the Grafana user interface using Kubernetes Port Forwarding:
```bash
# Port forward Grafana server to local port 3000
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```
1.  Open your browser and navigate to `http://localhost:3000`.
2.  Log in using credentials:
    *   **Username**: `admin`
    *   **Password**: `admin-secret-password-123` (configured in `terraform.tfvars` / `main.tf`)
3.  Go to **Dashboards** -> **Browse** to view built-in Kubernetes dashboards mapping CPU usage, Memory usage, Node Health, and Pod Health.

---

## Clean Up (Destroy Infrastructure)

To tear down all resources and avoid running AWS costs:
```bash
# Delete the sample application service first (cleans up the AWS Load Balancer)
kubectl delete svc nginx
kubectl delete deployment nginx

# Destroy all Terraform-managed resources
terraform destroy -auto-approve
```
