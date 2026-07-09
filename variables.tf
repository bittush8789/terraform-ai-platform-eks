variable "aws_region" {
  type        = string
  description = "The AWS Region where all resources will be provisioned."
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the Virtual Private Cloud (VPC)."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks for the public subnets (used for public ingress and NAT Gateway)."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks for the private subnets (where worker nodes and pods reside)."
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "cluster_name" {
  type        = string
  description = "The name of the Amazon EKS cluster."
  default     = "basic-eks-cluster"
}

variable "kubernetes_version" {
  type        = string
  description = "The target Kubernetes version for the EKS control plane."
  default     = "1.30"
}

variable "instance_types" {
  type        = list(string)
  description = "The EC2 instance type for the EKS managed node group worker nodes."
  default     = ["t3.medium"]
}

variable "disk_size" {
  type        = number
  description = "The root volume disk size (in GB) for the worker node EC2 instances."
  default     = 20
}

variable "scaling_desired_size" {
  type        = number
  description = "The desired number of active worker nodes in the node group."
  default     = 2
}

variable "scaling_min_size" {
  type        = number
  description = "The minimum scaling threshold of active worker nodes in the node group."
  default     = 1
}

variable "scaling_max_size" {
  type        = number
  description = "The maximum scaling limit of active worker nodes in the node group."
  default     = 3
}

variable "enable_monitoring" {
  type        = bool
  description = "Flag to determine if Prometheus, Grafana, and Metrics Server should be deployed via Helm."
  default     = true
}
