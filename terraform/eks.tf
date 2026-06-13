# =============================================================================
# EKS module — managed Kubernetes cluster for the e-commerce application
# Depends on: provider.tf (name, tags), vpc.tf (networking)
# =============================================================================
module "eks" {

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  # Step 1: Cluster identity and API access
  cluster_name                   = local.name
  cluster_endpoint_public_access = true # API reachable from internet (IAM-authenticated)

  # Step 2: Required cluster add-ons for networking and DNS
  cluster_addons = {
    coredns = {
      most_recent = true # In-cluster DNS
    }
    kube-proxy = {
      most_recent = true # Service traffic routing on nodes
    }
    vpc-cni = {
      most_recent = true # Assigns VPC IPs to pods
    }
  }

  # Step 3: Attach cluster to the VPC created in vpc.tf
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.public_subnets      # Worker nodes
  control_plane_subnet_ids = module.vpc.intra_subnets       # Control plane

  # Step 4: Default settings applied to all managed node groups
  eks_managed_node_group_defaults = {

    instance_types = ["t2.large"] # 2 vCPU, 8 GiB RAM

    attach_cluster_primary_security_group = true # Correct node ↔ control plane rules

  }

  # Step 5: Worker node pool — runs application pods
  eks_managed_node_groups = {

    Lucifer-demo-ng = {
      min_size     = 2 # Minimum nodes (always on)
      max_size     = 3 # Maximum nodes (autoscale ceiling)
      desired_size = 2 # Target node count at steady state

      instance_types = ["t2.large"]
      capacity_type  = "SPOT" # Cheaper; AWS may reclaim with short notice

      disk_size                  = 35
      use_custom_launch_template = false # Must be false for disk_size to apply

      tags = {
        Name        = "Lucifer-demo-ng"
        Environment = "dev"
        ExtraTag    = "e-commerce-app"
      }
    }
  }

  # Step 6: Apply shared project tags from provider.tf
  tags = local.tags

}

# =============================================================================
# Step 7: Look up running EKS worker instances after the cluster is created
# Used by: outputs.tf (eks_node_group_public_ips)
# =============================================================================
data "aws_instances" "eks_nodes" {

  instance_tags = {
    "eks:cluster-name" = module.eks.cluster_name
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [module.eks]

}
