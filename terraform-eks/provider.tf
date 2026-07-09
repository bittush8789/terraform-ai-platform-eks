provider "aws" {
  region = var.aws_region
}

# The Kubernetes provider dynamically connects to the EKS Cluster
provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

# The Helm provider dynamically connects to the EKS Cluster
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

# Retrieve an authentication token dynamically to configure kubernetes/helm providers
data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}
