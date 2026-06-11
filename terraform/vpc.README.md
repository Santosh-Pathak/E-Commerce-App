# VPC Infrastructure Guide — `vpc.tf`

> **Who is this for?** Anyone new to Terraform or AWS who wants to understand exactly what this project does, step by step, before running a single command.

---

## Table of Contents

1. [What does this file do?](#1-what-does-this-file-do)
2. [Files in this folder](#2-files-in-this-folder)
3. [Prerequisites](#3-prerequisites)
4. [How Terraform works (quick mental model)](#4-how-terraform-works-quick-mental-model)
5. [What vpc.tf does — step by step](#5-what-vpctf-does--step-by-step)
   - [Step 1 — Call the VPC Terraform module](#step-1--call-the-vpc-terraform-module)
   - [Step 2 — Name and size the network](#step-2--name-and-size-the-network)
   - [Step 3 — Create subnets across availability zones](#step-3--create-subnets-across-availability-zones)
   - [Step 4 — Enable NAT gateway](#step-4--enable-nat-gateway)
   - [Step 5 — Tag subnets for Kubernetes load balancers](#step-5--tag-subnets-for-kubernetes-load-balancers)
   - [Step 6 — Auto-assign public IPs](#step-6--auto-assign-public-ips)
6. [How the VPC connects to EKS](#6-how-the-vpc-connects-to-eks)
7. [Running Terraform — the full workflow](#7-running-terraform--the-full-workflow)
8. [AWS resources created (summary)](#8-aws-resources-created-summary)
9. [Quick reference diagram](#9-quick-reference-diagram)

---

## 1. What does this file do?

`vpc.tf` creates the **virtual network** where your EKS cluster and its worker nodes live. It uses the official **[terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws)** module instead of hand-writing dozens of networking resources.

The VPC is named **`Lucifer-eks-cluster`** (from `local.name` in `provider.tf`).

---

## 2. Files in this folder

```
terraform/
├── provider.tf    ← Defines region, CIDR blocks, subnet ranges (locals)
├── vpc.tf         ← This file: creates the VPC and subnets
├── eks.tf         ← EKS cluster — attaches to this VPC
├── ec2.tf         ← Jenkins server (uses default VPC separately)
└── vpc.README.md  ← This guide
```

> **Note:** The Jenkins EC2 instance in `ec2.tf` uses the **account default VPC**, not this custom VPC. Only EKS runs inside the VPC defined here.

---

## 3. Prerequisites

- `provider.tf` must define `local.name`, `local.vpc_cidr`, `local.azs`, and subnet CIDRs
- AWS credentials configured
- Terraform initialized (`terraform init`)

---

## 4. How Terraform works (quick mental model)

The VPC module is a pre-built recipe. You pass in names and IP ranges; it creates VPC, subnets, route tables, internet gateway, and (optionally) NAT gateway. `eks.tf` then plugs the cluster into specific subnets from this module.

---

## 5. What `vpc.tf` does — step by step

---

### Step 1 — Call the VPC Terraform module

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"
  ...
}
```

**What this does:**
Downloads and runs the community VPC module (version 4.x). The module creates and wires together standard networking resources.

**Why use a module?** VPC setup involves many resources (VPC, subnets, route tables, gateways). The module handles best practices and reduces errors.

---

### Step 2 — Name and size the network

```hcl
name = local.name          # "Lucifer-eks-cluster"
cidr = local.vpc_cidr      # "10.0.0.0/16"
azs  = local.azs           # ["eu-west-1a", "eu-west-1b"]
```

| Setting | Value | Meaning |
|---------|-------|---------|
| `name` | `Lucifer-eks-cluster` | VPC name in AWS Console |
| `cidr` | `10.0.0.0/16` | Private IP range for the whole network |
| `azs` | Two zones in `eu-west-1` | Spreads resources for fault tolerance |

---

### Step 3 — Create subnets across availability zones

```hcl
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
intra_subnets   = ["10.0.5.0/24", "10.0.6.0/24"]
```

**Subnet types:**

| Type | CIDR (per AZ) | Typical use in this project |
|------|---------------|----------------------------|
| **Public** | `10.0.1.0/24`, `10.0.2.0/24` | EKS worker nodes (`eks.tf` → `subnet_ids`) |
| **Private** | `10.0.3.0/24`, `10.0.4.0/24` | Internal workloads behind NAT |
| **Intra** | `10.0.5.0/24`, `10.0.6.0/24` | EKS control plane ENIs (`control_plane_subnet_ids`) |

Each subnet type exists in **two** AZs so one zone failure does not take down the cluster.

---

### Step 4 — Enable NAT gateway

```hcl
enable_nat_gateway = true
```

**What is a NAT gateway?**
Allows resources in **private** subnets to reach the internet (for pulling images, updates) without accepting inbound connections from the internet.

**Cost note:** NAT gateways incur hourly and data charges. Required for production-style private networking.

---

### Step 5 — Tag subnets for Kubernetes load balancers

```hcl
public_subnet_tags = {
  "kubernetes.io/role/elb" = 1
}

private_subnet_tags = {
  "kubernetes.io/role/internal-elb" = 1
}
```

**What these tags do:**
Tell AWS load balancer controllers which subnets to use when Kubernetes creates:

- **Public ELBs** — internet-facing services (HTTP/HTTPS ingress)
- **Internal ELBs** — cluster-internal load balancers

**Why this matters:** Without these tags, Kubernetes may fail to provision load balancers correctly.

---

### Step 6 — Auto-assign public IPs

```hcl
map_public_ip_on_launch = true
```

EC2 instances launched in **public** subnets automatically get a public IPv4 address. This helps EKS nodes (placed in public subnets in `eks.tf`) reach the internet and be reachable where needed.

---

## 6. How the VPC connects to EKS

`eks.tf` references this module:

```hcl
vpc_id                   = module.vpc.vpc_id
subnet_ids               = module.vpc.public_subnets
control_plane_subnet_ids = module.vpc.intra_subnets
```

```
module.vpc
├── public_subnets  ──► EKS worker nodes
├── intra_subnets   ──► EKS control plane
└── vpc_id          ──► Cluster network identity
```

The VPC must exist **before** EKS can be created. Terraform handles that order automatically.

---

## 7. Running Terraform — the full workflow

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

After apply, check outputs:

```bash
terraform output vpc_id
```

---

## 8. AWS resources created (summary)

| Resource | Name / detail | Purpose |
|----------|---------------|---------|
| VPC | `Lucifer-eks-cluster` | Isolated network for EKS |
| Public subnets | 2 × `/24` in `eu-west-1a/b` | Workers, public ELB placement |
| Private subnets | 2 × `/24` | Internal traffic via NAT |
| Intra subnets | 2 × `/24` | EKS control plane |
| Internet gateway | (via module) | Public internet for public subnets |
| NAT gateway | (via module) | Outbound internet for private subnets |
| Route tables | (via module) | Traffic routing per subnet type |

---

## 9. Quick reference diagram

```
provider.tf (locals)
      │
      ▼
module.vpc  ──► VPC: Lucifer-eks-cluster (10.0.0.0/16)
      │
      ├── public subnets  (10.0.1–2.x) ──► EKS nodes + public LBs
      ├── private subnets (10.0.3–4.x) ──► internal apps + NAT
      └── intra subnets   (10.0.5–6.x) ──► EKS control plane
      │
      ▼
module.eks (eks.tf)
```

---

*Read `vpc.tf` together with `provider.tf` (for CIDR values) and `eks.tf` (for how subnets are consumed).*
