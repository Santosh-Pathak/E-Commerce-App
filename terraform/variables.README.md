# Variables Guide — `variables.tf`

> **Who is this for?** Anyone new to Terraform or AWS who wants to understand exactly what this project does, step by step, before running a single command.

---

## Table of Contents

1. [What does this file do?](#1-what-does-this-file-do)
2. [Files in this folder](#2-files-in-this-folder)
3. [Prerequisites](#3-prerequisites)
4. [How Terraform variables work](#4-how-terraform-variables-work)
5. [What variables.tf defines — step by step](#5-what-variablestf-defines--step-by-step)
   - [Variable 1 — aws_region](#variable-1--aws_region)
   - [Variable 2 — instance_type](#variable-2--instance_type)
   - [Variable 3 — my_enviroment](#variable-3--my_enviroment)
   - [Commented variable — ami_id](#commented-variable--ami_id)
6. [How to pass variables when running Terraform](#6-how-to-pass-variables-when-running-terraform)
7. [Which files use which variables](#7-which-files-use-which-variables)
8. [Quick reference](#8-quick-reference)

---

## 1. What does this file do?

`variables.tf` declares **inputs** you can customize when running Terraform. Think of variables as knobs on the configuration — instance size, region overrides, environment name — without editing the main resource files.

Currently, only **`instance_type`** is actively used by `ec2.tf`. The others have defaults and are available for future use or overrides.

---

## 2. Files in this folder

```
terraform/
├── variables.tf         ← This file: input declarations
├── ec2.tf               ← Uses var.instance_type
├── provider.tf          ← Uses locals (not variables) for region/name
└── variables.README.md  ← This guide
```

---

## 3. Prerequisites

None specific to this file. Variables are read automatically when you run `terraform plan` or `terraform apply`.

---

## 4. How Terraform variables work

Each variable can have:

- **`description`** — What it's for (documentation)
- **`default`** — Value used if you don't pass anything
- **No default** — You must provide a value or Terraform will prompt you

Override methods:

```bash
# Command line
terraform apply -var="instance_type=t3.medium"

# Environment variable
export TF_VAR_instance_type=t3.medium
terraform apply

# terraform.tfvars file (create manually)
instance_type = "t3.medium"
```

---

## 5. What `variables.tf` defines — step by step

---

### Variable 1 — `aws_region`

```hcl
variable "aws_region" {
  description = "AWS region where resources will be provisioned"
  default     = "us-east-2"
}
```

| Field | Value |
|-------|-------|
| Default | `us-east-2` (Ohio) |
| Currently used? | **No** — `provider.tf` hard-codes `local.region = "eu-west-1"` |

**Note for first-time readers:** The project actually deploys to **`eu-west-1`** via `provider.tf`, not `us-east-2`. This variable is declared but not wired to the provider yet. To use it, you would change `provider.tf` to `region = var.aws_region`.

---

### Variable 2 — `instance_type`

```hcl
variable "instance_type" {
  description = "Instance type for the EC2 instance"
  default     = "t2.medium"
}
```

| Field | Value |
|-------|-------|
| Default | `t2.medium` |
| Used by | `ec2.tf` → `aws_instance.testinstance` |

**What it controls:** CPU and RAM for the Jenkins/DevOps EC2 server.

| Instance type | vCPUs | RAM | Notes |
|---------------|-------|-----|-------|
| `t2.medium` | 2 | 4 GB | Default in this file |
| `t3.medium` | 2 | 4 GB | Often recommended for Jenkins |
| `t2.large` | 2 | 8 GB | More headroom |

---

### Variable 3 — `my_enviroment`

```hcl
variable "my_enviroment" {
  description = "Instance type for the EC2 instance"
  default     = "dev"
}
```

| Field | Value |
|-------|-------|
| Default | `dev` |
| Currently used? | **No** — not referenced in other `.tf` files yet |

**Note:** The variable name is spelled `my_enviroment` (typo for "environment"). The description also duplicates the instance_type text — likely copy-paste. Reserved for tagging or environment-specific logic later.

---

### Commented variable — `ami_id`

```hcl
# variable "ami_id" {
#   description = "AMI ID for the EC2 instance"
#   default     = "ami-085f9c64a9b75eed5"
# }
```

**Why it's commented out:** `ec2.tf` uses a **data source** to dynamically find the latest Ubuntu 24.04 AMI instead of a fixed AMI ID. Hard-coding AMI IDs breaks when AWS publishes new images or when you change regions.

---

## 6. How to pass variables when running Terraform

### Use defaults (simplest)

```bash
terraform apply
```

`instance_type` defaults to `t2.medium`.

### Override on the command line

```bash
terraform plan -var="instance_type=t3.medium"
terraform apply -var="instance_type=t3.medium"
```

### Use a `terraform.tfvars` file

Create `terraform/terraform.tfvars`:

```hcl
instance_type   = "t3.medium"
my_enviroment   = "dev"
```

Terraform loads this file automatically.

---

## 7. Which files use which variables

| Variable | Used in | Status |
|----------|---------|--------|
| `var.instance_type` | `ec2.tf` | Active |
| `var.aws_region` | — | Declared only |
| `var.my_enviroment` | — | Declared only |
| `var.ami_id` | — | Commented out |

**Locals vs variables:**

| Source | File | Examples |
|--------|------|----------|
| `local.*` | `provider.tf` | `Lucifer-eks-cluster`, `eu-west-1`, subnet CIDRs |
| `var.*` | `variables.tf` | `instance_type`, `aws_region` |

---

## 8. Quick reference

```
variables.tf
├── aws_region      (default: us-east-2)     → not wired yet
├── instance_type   (default: t2.medium)     → ec2.tf
├── my_enviroment   (default: dev)           → not wired yet
└── ami_id          (commented)              → replaced by data.aws_ami
```

---

*When in doubt, run `terraform plan` — it shows which variable values Terraform will use for each resource.*
