# Provider & Locals Guide — `provider.tf`

> **Who is this for?** Anyone new to Terraform or AWS who wants to understand exactly what this project does, step by step, before running a single command.

---

## Table of Contents

1. [What does this file do?](#1-what-does-this-file-do)
2. [Files in this folder](#2-files-in-this-folder)
3. [Prerequisites](#3-prerequisites)
4. [How this file fits the bigger picture](#4-how-this-file-fits-the-bigger-picture)
5. [What provider.tf does — step by step](#5-what-providertf-does--step-by-step)
   - [Step 1 — Define shared locals](#step-1--define-shared-locals)
   - [Step 2 — Configure the AWS provider](#step-2--configure-the-aws-provider)
6. [Running Terraform — the full workflow](#6-running-terraform--the-full-workflow)
7. [Values other files depend on](#7-values-other-files-depend-on)
8. [Quick reference diagram](#8-quick-reference-diagram)

---

## 1. What does this file do?

`provider.tf` is the **foundation** of the Terraform project. It does two things:

1. **`locals` block** — Defines shared constants (region, cluster name, network CIDRs, tags) used by `vpc.tf`, `eks.tf`, and `outputs.tf`
2. **`provider "aws"` block** — Tells Terraform which cloud to talk to and which AWS region to use

Every other `.tf` file in this folder references values from here (especially `local.name` and `local.region`).

---

## 2. Files in this folder

```
terraform/
├── provider.tf           ← This file: region, cluster name, network constants
├── variables.tf          ← User inputs (instance type, etc.)
├── vpc.tf                ← VPC module (uses locals from here)
├── eks.tf                ← EKS cluster (uses local.name)
├── ec2.tf                ← Jenkins EC2 server
├── outputs.tf            ← Prints values after apply
└── provider.README.md    ← This guide
```

---

## 3. Prerequisites

- AWS account with programmatic access (Access Key + Secret Key)
- AWS CLI configured: `aws configure`
- Terraform installed: `terraform -version`

---

## 4. How this file fits the bigger picture

When you run `terraform apply`, Terraform loads **all** `.tf` files together. `provider.tf` runs first conceptually because other files need its values:

```
provider.tf (locals + AWS provider)
      │
      ├──► vpc.tf      uses local.name, local.vpc_cidr, local.azs, subnets
      ├──► eks.tf      uses local.name, local.tags, module.vpc
      ├──► ec2.tf      uses var.instance_type (separate from locals)
      └──► outputs.tf  uses local.region, module outputs
```

---

## 5. What `provider.tf` does — step by step

---

### Step 1 — Define shared locals

```hcl
locals {
  region          = "eu-west-1"
  name            = "Lucifer-eks-cluster"
  vpc_cidr        = "10.0.0.0/16"
  azs             = ["eu-west-1a", "eu-west-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  intra_subnets   = ["10.0.5.0/24", "10.0.6.0/24"]
  tags = {
    example = local.name
  }
}
```

**What are locals?**
Locals are named values you compute once and reuse across the project. They are not inputs from the user — they are fixed configuration decided by the project authors.

**Each value explained:**

| Local | Value | Purpose |
|-------|-------|---------|
| `region` | `eu-west-1` | AWS region (Ireland) — all resources deploy here |
| `name` | `Lucifer-eks-cluster` | Cluster name used for VPC naming and EKS |
| `vpc_cidr` | `10.0.0.0/16` | Total IP range for the VPC (65,536 addresses) |
| `azs` | `eu-west-1a`, `eu-west-1b` | Two availability zones for high availability |
| `public_subnets` | `10.0.1.0/24`, `10.0.2.0/24` | Subnets with direct internet access |
| `private_subnets` | `10.0.3.0/24`, `10.0.4.0/24` | Subnets routed through NAT gateway |
| `intra_subnets` | `10.0.5.0/24`, `10.0.6.0/24` | Isolated subnets for EKS control plane |
| `tags` | `{ example = local.name }` | Default tags applied to EKS resources |

**Why this matters:** Changing `local.name` renames the VPC and EKS cluster everywhere consistently. Changing `region` affects every AWS API call.

---

### Step 2 — Configure the AWS provider

```hcl
provider "aws" {
  region = local.region
}
```

**What is a provider?**
A provider is Terraform's plugin for a specific platform. The `aws` provider knows how to create VPCs, EC2 instances, EKS clusters, etc.

**What this block does:**
Sets the default AWS region to `eu-west-1` (from `local.region`). All resources without an explicit region use this.

**Authentication:** Terraform uses the same credentials as the AWS CLI (`aws configure`) or environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

**Why this matters:** Without a provider, Terraform cannot talk to AWS at all.

---

## 6. Running Terraform — the full workflow

`provider.tf` is not applied separately — it is part of the whole project:

```bash
cd terraform
terraform init    # Downloads the AWS provider plugin
terraform plan    # Preview all resources
terraform apply   # Create everything
```

---

## 7. Values other files depend on

| Local / provider | Used by | For what |
|------------------|---------|----------|
| `local.name` | `vpc.tf`, `eks.tf` | VPC name, EKS cluster name |
| `local.region` | `provider`, `outputs.tf` | AWS region |
| `local.vpc_cidr`, `local.azs`, subnets | `vpc.tf` | Network layout |
| `local.tags` | `eks.tf` | Resource tagging |
| `provider "aws"` | All resources | AWS API access |

---

## 8. Quick reference diagram

```
provider.tf
├── locals
│   ├── region  ──────────► eu-west-1
│   ├── name    ──────────► Lucifer-eks-cluster
│   ├── vpc_cidr / azs / subnets ──► vpc.tf
│   └── tags    ──────────► eks.tf
│
└── provider "aws"
    └── region = local.region ──► All AWS resources
```

---

*Read `provider.tf` first when exploring this project — every network and cluster name flows from the `locals` block.*
