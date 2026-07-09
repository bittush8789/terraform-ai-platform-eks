# ==============================================================================
# AWS Provider & Availability Zone Configuration
# ==============================================================================

# Look up available Availability Zones in the current region
data "aws_availability_zones" "available" {
  state = "available"
}

# ==============================================================================
# Networking: VPC & Subnets
# ==============================================================================

# Create a Virtual Private Cloud (VPC)
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                      = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Create Public Subnets (used for ingress controllers, ALBs, and NAT Gateway)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                      = "${var.cluster_name}-public-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                  = "1" # Required for public external LoadBalancers
  }
}

# Create Private Subnets (used for EKS worker nodes and secure workloads)
resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name                                      = "${var.cluster_name}-private-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"         = "1" # Required for private internal LoadBalancers
  }
}

# ==============================================================================
# Networking: Internet & NAT Gateways
# ==============================================================================

# Create an Internet Gateway (IGW) to allow internet ingress/egress for public subnets
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Allocate an Elastic IP for the NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

# Create a NAT Gateway in the first public subnet to allow outbound traffic for private subnets
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.cluster_name}-nat-gw"
  }

  # Ensure the Internet Gateway is created before the NAT Gateway
  depends_on = [aws_internet_gateway.this]
}

# ==============================================================================
# Networking: Routing Tables & Associations
# ==============================================================================

# Route Table for Public Subnets (routes directly to the Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# Associate Public Subnets with the Public Route Table
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table for Private Subnets (routes outbound traffic to the NAT Gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

# Associate Private Subnets with the Private Route Table
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ==============================================================================
# IAM Roles & Policies for EKS Control Plane
# ==============================================================================

# IAM Role assumed by the EKS Cluster Control Plane
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-cluster-role"
  }
}

# Attach standard AWS policy for EKS Cluster Control Plane
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# ==============================================================================
# IAM Roles & Policies for Worker Nodes
# ==============================================================================

# IAM Role assumed by worker nodes (EC2 instances)
resource "aws_iam_role" "nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-node-role"
  }
}

# Attach AWS policy allowing EKS node agent to connect to control plane
resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
}

# Attach AWS policy for VPC CNI plugin to configure IP allocations for pods
resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
}

# Attach AWS policy allowing worker nodes read-only access to ECR images
resource "aws_iam_role_policy_attachment" "registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
}

# ==============================================================================
# Security Groups: Control Plane & Worker Nodes
# ==============================================================================

# Control Plane Cluster Security Group
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS Control plane communication security group"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

# Worker Nodes Security Group
resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for all EKS worker nodes"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name                                      = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Ingress: Allow Worker Nodes to communicate with the EKS API Server (Port 443)
resource "aws_security_group_rule" "cluster_ingress_node_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Allow worker nodes to talk to Kubernetes API server"
}

# Egress: Control Plane to Kubelet port on Worker Nodes (Port 10250)
resource "aws_security_group_rule" "cluster_egress_node_kubelet" {
  type                     = "egress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Allow control plane to talk to kubelet service on worker nodes"
}

# Egress: Control Plane to Node ephemeral ports for Webhooks
resource "aws_security_group_rule" "cluster_egress_node_ephemeral" {
  type                     = "egress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Allow control plane to talk to node workloads on ephemeral ports"
}

# Ingress: Allow Control Plane to communicate with Node Webhooks (Port 443)
resource "aws_security_group_rule" "node_ingress_cluster_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Allow control plane to talk to webhooks running on worker nodes"
}

# Ingress: Allow Control Plane to communicate with Kubelet (Port 10250)
resource "aws_security_group_rule" "node_ingress_cluster_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Allow control plane to query metrics/logs via kubelet"
}

# Ingress: Allow Control Plane to communicate with Node ephemeral ports
resource "aws_security_group_rule" "node_ingress_cluster_ephemeral" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Allow control plane to send traffic to pod workloads on ephemeral ports"
}

# Ingress: Allow unrestricted intra-node communications (between worker nodes)
resource "aws_security_group_rule" "node_ingress_self" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Allow all internal communication between worker nodes"
}

# Egress: Control Plane Internet Access
resource "aws_security_group_rule" "cluster_egress_internet" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.cluster.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow control plane outbound traffic"
}

# Egress: Worker Nodes Internet Access
resource "aws_security_group_rule" "node_egress_internet" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.nodes.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow worker nodes outbound traffic for internet/package downloads"
}

# ==============================================================================
# Amazon EKS Cluster
# ==============================================================================

# Deploy the managed Amazon EKS Cluster
resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    # Distribute control plane network interfaces across all public & private subnets
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true # Enable secure access inside the VPC
    endpoint_public_access  = true # Enable access from outside the VPC (configured via API)
  }

  # Enable CloudWatch logging for EKS control plane components
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Explicitly wait for the cluster IAM policies to be attached before cluster creation
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# ==============================================================================
# Managed Node Group
# ==============================================================================

# Deploy the worker node instances as a managed node group inside private subnets
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.private[*].id # Launch worker nodes in secure private subnets

  scaling_config {
    desired_size = var.scaling_desired_size
    min_size     = var.scaling_min_size
    max_size     = var.scaling_max_size
  }

  instance_types = var.instance_types
  disk_size      = var.disk_size
  ami_type       = "AL2023_x86_64_STANDARD" # Amazon Linux 2023 OS

  # Ensure role policies are attached before nodes start launching
  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.registry_policy
  ]
}

# ==============================================================================
# Helm Deployments (Metrics Server & Prometheus Monitoring Stack)
# ==============================================================================

# Namespace for hosting the Prometheus-Grafana stack
resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring ? 1 : 0

  metadata {
    name = "monitoring"
  }

  depends_on = [
    aws_eks_node_group.nodes
  ]
}

# Deploy the Kubernetes Metrics Server (required for Pod/Node cpu/memory metrics)
resource "helm_release" "metrics_server" {
  count = var.enable_monitoring ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-infrastructure/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  depends_on = [
    aws_eks_node_group.nodes
  ]
}

# Deploy Prometheus and Grafana (via Kube Prometheus Stack Helm Chart)
resource "helm_release" "prometheus_stack" {
  count = var.enable_monitoring ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  # Override standard Grafana settings to provide a default administrator password
  set {
    name  = "grafana.adminPassword"
    value = "admin-secret-password-123"
  }

  # Ensure the node group, namespace, and metrics server are fully operational before deploying
  depends_on = [
    aws_eks_node_group.nodes,
    kubernetes_namespace.monitoring,
    helm_release.metrics_server
  ]
}
