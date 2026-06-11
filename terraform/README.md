# Terraform — Infrastructure Overview

This folder provisions AWS infrastructure for the e-commerce app: networking (VPC), Kubernetes (EKS), and a Jenkins/DevOps EC2 server.

## Per-file guides

| Terraform file | README |
|----------------|--------|
| `provider.tf` | [provider.README.md](./provider.README.md) — AWS provider, region, shared locals |
| `variables.tf` | [variables.README.md](./variables.README.md) — Input variables |
| `vpc.tf` | [vpc.README.md](./vpc.README.md) — VPC, subnets, NAT gateway |
| `eks.tf` | [eks.README.md](./eks.README.md) — EKS cluster and node group |
| `ec2.tf` | [ec2.README.md](./ec2.README.md) — Jenkins/DevOps EC2 instance |
| `outputs.tf` | [outputs.README.md](./outputs.README.md) — Values printed after apply |

## Quick start

```bash
cd terraform
ssh-keygen -f terra-key
chmod 400 terra-key
terraform init
terraform plan
terraform apply
```

## Connect to EKS after apply

```bash
aws eks update-kubeconfig --region eu-west-1 --name Lucifer-eks-cluster
kubectl get nodes
```
