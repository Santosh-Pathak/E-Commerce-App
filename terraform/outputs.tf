# =============================================================================
# Outputs — values printed after terraform apply for easy access
# Read anytime with: terraform output
# =============================================================================

# Region where resources were deployed
output "region" {
  description = "The AWS region where resources are created"
  value       = local.region
}

# VPC identifier — useful for networking debug and AWS Console lookups
output "vpc_id" {
  description = "The ID of the created VPC"
  value       = module.vpc.vpc_id
}

# Cluster name — use with: aws eks update-kubeconfig --name <this-value>
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

# Kubernetes API endpoint — use with kubectl cluster-info
output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

# Jenkins server IP — use with: ssh -i terra-key ubuntu@<this-value>
output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.testinstance.public_ip
}

# EKS worker node IPs — verify node count matches desired_size in eks.tf
output "eks_node_group_public_ips" {
  description = "Public IPs of the EKS node group instances"
  value       = data.aws_instances.eks_nodes.public_ips
}
