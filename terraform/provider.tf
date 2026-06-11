# =============================================================================
# Step 1: Shared configuration (locals)
# Values defined here are reused by vpc.tf, eks.tf, and outputs.tf
# =============================================================================
locals {

  # AWS region where all resources in this project are deployed
  region = "eu-west-1"

  # Cluster and VPC name — used consistently across networking and EKS
  name = "Lucifer-eks-cluster"

  # Total IP address range for the custom VPC (65,536 addresses)
  vpc_cidr = "10.0.0.0/16"

  # Two availability zones for high availability across the region
  azs = ["eu-west-1a", "eu-west-1b"]

  # Public subnets: internet-facing; used by EKS worker nodes
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # Private subnets: outbound internet via NAT; internal workloads
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  # Intra subnets: isolated; used by the EKS control plane
  intra_subnets = ["10.0.5.0/24", "10.0.6.0/24"]

  # Default tags applied to EKS resources
  tags = {
    example = local.name
  }

}

# =============================================================================
# Step 2: AWS provider
# Tells Terraform which cloud platform and region to use for all resources
# =============================================================================
provider "aws" {

  region = local.region

}
