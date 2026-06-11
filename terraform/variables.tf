# =============================================================================
# Input variables — customizable values passed into Terraform at apply time
# Override via: terraform apply -var="instance_type=t3.medium"
# or a terraform.tfvars file
# =============================================================================

# AWS region override (declared for flexibility; provider.tf currently uses local.region)
variable "aws_region" {
  description = "AWS region where resources will be provisioned"
  default     = "us-east-2"
}

# Hard-coded AMI ID — commented out because ec2.tf dynamically looks up Ubuntu 24.04
# variable "ami_id" {
#   description = "AMI ID for the EC2 instance"
#   default     = "ami-085f9c64a9b75eed5"
# }

# EC2 instance size for the Jenkins/DevOps server (used in ec2.tf)
variable "instance_type" {
  description = "Instance type for the EC2 instance"
  default     = "t2.medium"
}

# Environment label (reserved for future tagging or environment-specific logic)
variable "my_enviroment" {
  description = "Instance type for the EC2 instance"
  default     = "dev"
}
