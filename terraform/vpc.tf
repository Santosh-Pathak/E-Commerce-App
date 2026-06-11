# =============================================================================
# VPC module — creates the virtual network for the EKS cluster
# Depends on: provider.tf (locals for name, CIDR, subnets, AZs)
# Used by: eks.tf (cluster and nodes attach to this VPC)
# =============================================================================
module "vpc" {

  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  # Step 1: Name and size the VPC using shared locals from provider.tf
  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  # Step 2: Create subnet tiers across both availability zones
  public_subnets  = local.public_subnets  # EKS workers, public load balancers
  private_subnets = local.private_subnets  # Internal apps behind NAT
  intra_subnets   = local.intra_subnets    # EKS control plane ENIs

  # Step 3: Allow private subnets to reach the internet for image pulls and updates
  enable_nat_gateway = true

  # Step 4: Tag subnets so Kubernetes can place load balancers correctly
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1 # Internet-facing ELBs
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1 # Internal ELBs
  }

  # Step 5: Auto-assign public IPs to instances launched in public subnets
  map_public_ip_on_launch = true

}
