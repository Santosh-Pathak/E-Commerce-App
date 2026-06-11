# Outputs Guide — `outputs.tf`

> **Who is this for?** Anyone new to Terraform or AWS who wants to understand exactly what this project does, step by step, before running a single command.

---

## Table of Contents

1. [What does this file do?](#1-what-does-this-file-do)
2. [Files in this folder](#2-files-in-this-folder)
3. [Prerequisites](#3-prerequisites)
4. [How Terraform outputs work](#4-how-terraform-outputs-work)
5. [What outputs.tf defines — step by step](#5-what-outputstf-defines--step-by-step)
   - [Output 1 — region](#output-1--region)
   - [Output 2 — vpc_id](#output-2--vpc_id)
   - [Output 3 — eks_cluster_name](#output-3--eks_cluster_name)
   - [Output 4 — eks_cluster_endpoint](#output-4--eks_cluster_endpoint)
   - [Output 5 — public_ip](#output-5--public_ip)
   - [Output 6 — eks_node_group_public_ips](#output-6--eks_node_group_public_ips)
6. [How to read outputs after apply](#6-how-to-read-outputs-after-apply)
7. [What to do with each output](#7-what-to-do-with-each-output)
8. [Quick reference diagram](#8-quick-reference-diagram)

---

## 1. What does this file do?

`outputs.tf` declares **values Terraform prints** after a successful `terraform apply`. Instead of hunting through the AWS Console, you get the important connection details in your terminal:

- Where the cluster is (`region`, `vpc_id`, `eks_cluster_name`)
- How to reach the API (`eks_cluster_endpoint`)
- How to SSH to Jenkins (`public_ip`)
- Worker node IPs (`eks_node_group_public_ips`)

Outputs do **not** create AWS resources — they only expose information from resources already created.

---

## 2. Files in this folder

```
terraform/
├── outputs.tf         ← This file: values shown after apply
├── provider.tf        ← Supplies local.region
├── vpc.tf             ← Supplies module.vpc.vpc_id
├── eks.tf             ← Supplies module.eks.* and data.aws_instances.eks_nodes
├── ec2.tf             ← Supplies aws_instance.testinstance.public_ip
└── outputs.README.md  ← This guide
```

---

## 3. Prerequisites

Run `terraform apply` successfully first. Outputs only exist after infrastructure is created.

---

## 4. How Terraform outputs work

After apply, Terraform stores output values in its state file. You can read them anytime:

```bash
terraform output                    # All outputs
terraform output public_ip          # One output
terraform output -json              # Machine-readable JSON
```

---

## 5. What `outputs.tf` defines — step by step

---

### Output 1 — `region`

```hcl
output "region" {
  description = "The AWS region where resources are created"
  value       = local.region
}
```

| Value | Example |
|-------|---------|
| `eu-west-1` | From `provider.tf` |

**Use it for:** `aws eks update-kubeconfig --region <region>`, scripting, documentation.

---

### Output 2 — `vpc_id`

```hcl
output "vpc_id" {
  description = "The ID of the created VPC"
  value       = module.vpc.vpc_id
}
```

| Value | Example |
|-------|---------|
| `vpc-0abc123...` | AWS VPC identifier |

**Use it for:** Debugging networking, peering, security group rules, AWS Console deep links.

---

### Output 3 — `eks_cluster_name`

```hcl
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}
```

| Value | Example |
|-------|---------|
| `Lucifer-eks-cluster` | From `local.name` |

**Use it for:**

```bash
aws eks update-kubeconfig --region eu-west-1 --name Lucifer-eks-cluster
```

---

### Output 4 — `eks_cluster_endpoint`

```hcl
output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}
```

| Value | Example |
|-------|---------|
| `https://XXXX.gr7.eu-west-1.eks.amazonaws.com` | Kubernetes API URL |

**Use it for:** Verifying the API server URL, CI/CD configuration, `kubectl cluster-info`.

---

### Output 5 — `public_ip`

```hcl
output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.testinstance.public_ip
}
```

| Value | Example |
|-------|---------|
| `54.x.x.x` | Jenkins server public IP |

**Use it for:**

```bash
ssh -i terra-key ubuntu@<public_ip>
# Jenkins UI: http://<public_ip>:8080
```

---

### Output 6 — `eks_node_group_public_ips`

```hcl
output "eks_node_group_public_ips" {
  description = "Public IPs of the EKS node group instances"
  value       = data.aws_instances.eks_nodes.public_ips
}
```

| Value | Example |
|-------|---------|
| List of IPs | One per running worker in `Lucifer-demo-ng` |

**Use it for:** Debugging node connectivity, SSH to workers (if allowed), verifying node count matches `desired_size = 2`.

**Depends on:** `data.aws_instances.eks_nodes` in `eks.tf`, which tags instances with `eks:cluster-name = Lucifer-eks-cluster`.

---

## 6. How to read outputs after apply

```bash
cd terraform

# All outputs at end of apply
terraform apply

# Query later
terraform output
terraform output public_ip
terraform output eks_cluster_name
```

Example:

```
eks_cluster_name = "Lucifer-eks-cluster"
public_ip = "54.198.x.x"
region = "eu-west-1"
```

---

## 7. What to do with each output

| Output | Next step |
|--------|-----------|
| `region` + `eks_cluster_name` | `aws eks update-kubeconfig --region eu-west-1 --name Lucifer-eks-cluster` |
| `eks_cluster_endpoint` | `kubectl cluster-info` |
| `public_ip` | SSH and open Jenkins on port 8080 |
| `vpc_id` | Reference in AWS Console or other IaC |
| `eks_node_group_public_ips` | `kubectl get nodes` should show matching worker count |

---

## 8. Quick reference diagram

```
terraform apply
      │
      ├──► output.region              ← local.region (eu-west-1)
      ├──► output.vpc_id              ← module.vpc
      ├──► output.eks_cluster_name    ← Lucifer-eks-cluster
      ├──► output.eks_cluster_endpoint← Kubernetes API URL
      ├──► output.public_ip           ← Jenkins EC2
      └──► output.eks_node_group_public_ips ← EKS workers
```

---

*Run `terraform output` immediately after apply to copy IPs and cluster name without opening the AWS Console.*
