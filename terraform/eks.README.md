# EKS Infrastructure Guide — `eks.tf`

> **Who is this for?** Anyone new to Terraform or AWS who wants to understand exactly what this project does, step by step, before running a single command.

---

## Table of Contents

1. [What does this file do?](#1-what-does-this-file-do)
2. [Files in this folder](#2-files-in-this-folder)
3. [Prerequisites — do these before anything else](#3-prerequisites--do-these-before-anything-else)
4. [How Terraform works (quick mental model)](#4-how-terraform-works-quick-mental-model)
5. [What eks.tf does — step by step](#5-what-ekstf-does--step-by-step)
   - [Step 1 — Call the EKS Terraform module](#step-1--call-the-eks-terraform-module)
   - [Step 2 — Name the cluster and expose the API](#step-2--name-the-cluster-and-expose-the-api)
   - [Step 3 — Install cluster add-ons](#step-3--install-cluster-add-ons)
   - [Step 4 — Attach the cluster to the VPC](#step-4--attach-the-cluster-to-the-vpc)
   - [Step 5 — Set node group defaults](#step-5--set-node-group-defaults)
   - [Step 6 — Create the managed node group Lucifer-demo-ng](#step-6--create-the-managed-node-group-lucifer-demo-ng)
   - [Step 7 — Apply shared tags](#step-7--apply-shared-tags)
   - [Step 8 — Discover running worker instances](#step-8--discover-running-worker-instances)
6. [How EKS fits with the rest of this project](#6-how-eks-fits-with-the-rest-of-this-project)
7. [Running Terraform — the full workflow](#7-running-terraform--the-full-workflow)
8. [After deployment — connect with kubectl](#8-after-deployment--connect-with-kubectl)
9. [Tearing it all down](#9-tearing-it-all-down)
10. [AWS resources created (summary)](#10-aws-resources-created-summary)
11. [Security reminders before going to production](#11-security-reminders-before-going-to-production)
12. [Quick reference diagram](#12-quick-reference-diagram)

---

## 1. What does this file do?

`eks.tf` provisions an **Amazon EKS (Elastic Kubernetes Service)** cluster — a managed Kubernetes environment where this e-commerce application runs in production.

Instead of writing every AWS resource by hand, it uses the official **[terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws)** module (version `19.15.1`).

| Component | What it is |
|-----------|------------|
| **Control plane** | AWS-managed Kubernetes API (masters) |
| **Node group** | EC2 workers that run your application pods |
| **Add-ons** | CoreDNS, kube-proxy, vpc-cni — required cluster services |

Cluster name: **`Lucifer-eks-cluster`** (from `local.name` in `provider.tf`).

---

## 2. Files in this folder

```
terraform/
├── provider.tf    ← Cluster name, region, tags (locals)
├── vpc.tf         ← Network — must exist before EKS
├── eks.tf         ← This file: EKS cluster + node group
├── ec2.tf         ← Jenkins/DevOps server (separate from EKS workers)
├── outputs.tf     ← Prints cluster name, endpoint, node IPs
└── eks.README.md  ← This guide
```

---

## 3. Prerequisites — do these before anything else

1. **AWS credentials** with permissions for EKS, EC2, IAM, and VPC
2. **Terraform** installed and initialized (`terraform init`)
3. **`provider.tf` and `vpc.tf`** present — EKS depends on `module.vpc`
4. **Region** — project uses **`eu-west-1`** (Ireland)

EKS creation typically takes **10–20 minutes** on first apply.

---

## 4. How Terraform works (quick mental model)

`eks.tf` does not run alone. Terraform merges every `.tf` file in the folder:

```
vpc.tf creates network  →  eks.tf creates cluster in that network  →  outputs.tf shows connection info
```

The EKS module creates IAM roles, security groups, the control plane, add-ons, and managed node groups in the correct order.

---

## 5. What `eks.tf` does — step by step

```
Step 1 → Call EKS module
Step 2 → Set cluster name + public API access
Step 3 → Install add-ons (CoreDNS, kube-proxy, vpc-cni)
Step 4 → Wire VPC + subnets
Step 5 → Node group defaults
Step 6 → Create Lucifer-demo-ng node group
Step 7 → Apply tags
Step 8 → Look up running worker EC2 instances
```

---

### Step 1 — Call the EKS Terraform module

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.1"
  ...
}
```

**What this does:**
Pulls a battle-tested community module that knows how to build EKS correctly — IAM, security groups, control plane, and node groups.

**Why pin version `19.15.1`?** Upgrades are intentional; unpinned modules can change behavior unexpectedly.

---

### Step 2 — Name the cluster and expose the API

```hcl
cluster_name                   = local.name
cluster_endpoint_public_access = true
```

| Setting | Value | Meaning |
|---------|-------|---------|
| `cluster_name` | `Lucifer-eks-cluster` | Name in AWS Console and `kubectl` config |
| `cluster_endpoint_public_access` | `true` | Kubernetes API reachable from the internet (with IAM auth) |

**Why public access?** Simpler for Jenkins, bastion hosts, and local `kubectl` without VPN. Restrict in production.

---

### Step 3 — Install cluster add-ons

```hcl
cluster_addons = {
  coredns    = { most_recent = true }
  kube-proxy = { most_recent = true }
  vpc-cni    = { most_recent = true }
}
```

| Add-on | Purpose |
|--------|---------|
| **vpc-cni** | Assigns VPC IP addresses to pods |
| **kube-proxy** | Routes Service traffic to pods on each node |
| **coredns** | In-cluster DNS (e.g. `my-svc.default.svc.cluster.local`) |

`most_recent = true` installs the latest version compatible with your cluster version.

**Why this matters:** Without these, pods cannot get IPs, Services fail, and DNS breaks.

---

### Step 4 — Attach the cluster to the VPC

```hcl
vpc_id                   = module.vpc.vpc_id
subnet_ids               = module.vpc.public_subnets
control_plane_subnet_ids = module.vpc.intra_subnets
```

| Input | Used for |
|-------|----------|
| `vpc_id` | Which network the cluster belongs to |
| `subnet_ids` (public) | **EKS worker nodes** |
| `control_plane_subnet_ids` (intra) | **EKS control plane** network interfaces |

See [vpc.README.md](./vpc.README.md) for subnet layout details.

---

### Step 5 — Set node group defaults

```hcl
eks_managed_node_group_defaults = {
  instance_types = ["t2.large"]
  attach_cluster_primary_security_group = true
}
```

Defaults for every managed node group unless overridden:

- **`t2.large`** — 2 vCPU, 8 GiB RAM
- **`attach_cluster_primary_security_group`** — Correct control-plane ↔ node firewall rules

---

### Step 6 — Create the managed node group `Lucifer-demo-ng`

```hcl
eks_managed_node_groups = {
  Lucifer-demo-ng = {
    min_size     = 2
    max_size     = 3
    desired_size = 2
    instance_types = ["t2.large"]
    capacity_type  = "SPOT"
    disk_size = 35
    use_custom_launch_template = false
    tags = {
      Name        = "Lucifer-demo-ng"
      Environment = "dev"
      ExtraTag    = "easyshop"
    }
  }
}
```

**What is a managed node group?**
AWS creates and maintains EC2 instances that register as Kubernetes nodes. You set min/max/desired counts; AWS handles launch templates and scaling.

| Setting | Value | Meaning |
|---------|-------|---------|
| `min_size` / `max_size` / `desired_size` | 2 / 3 / 2 | Always 2 nodes; can scale to 3 |
| `capacity_type` | `SPOT` | Cheaper instances; AWS can reclaim with short notice |
| `disk_size` | 35 GB | Root volume per node |
| `use_custom_launch_template` | `false` | Required so `disk_size` applies correctly |

**Why SPOT?** Cost savings for dev/demo. Use `ON_DEMAND` for production stability.

---

### Step 7 — Apply shared tags

```hcl
tags = local.tags
```

Applies project tags from `provider.tf` to EKS resources for billing and filtering.

---

### Step 8 — Discover running worker instances

```hcl
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
```

**What this does:**
Does **not** create resources. After the cluster exists, Terraform **queries** EC2 for running instances tagged `eks:cluster-name = Lucifer-eks-cluster`.

**Used by:** `outputs.tf` → `eks_node_group_public_ips`

---

## 6. How EKS fits with the rest of this project

```
┌─────────────────┐     build/push      ┌──────────────────┐
│  Jenkins EC2    │ ──────────────────► │  Container       │
│  (ec2.tf)       │                     │  Registry (ECR)  │
└────────┬────────┘                     └────────┬─────────┘
         │ kubectl / helm / argocd               │ pull images
         ▼                                       ▼
┌─────────────────────────────────────────────────────────────┐
│  EKS: Lucifer-eks-cluster (eks.tf)                        │
│  Node group: Lucifer-demo-ng (2× t2.large SPOT)            │
│  Pods: e-commerce app, Argo CD, ingress, cert-manager      │
└─────────────────────────────────────────────────────────────┘
```

- **`ec2.tf`** — CI/CD tooling (Jenkins, Docker, kubectl)
- **`eks.tf`** — Where the app actually runs in Kubernetes

---

## 7. Running Terraform — the full workflow

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

EKS is created together with VPC and EC2 — not as a separate command.

---

## 8. After deployment — connect with kubectl

### Update kubeconfig

```bash
aws configure   # if not already done
aws eks update-kubeconfig --region eu-west-1 --name Lucifer-eks-cluster
```

Or use Terraform outputs:

```bash
terraform output eks_cluster_name
terraform output eks_cluster_endpoint
```

### Verify the cluster

```bash
kubectl cluster-info
kubectl get nodes
```

You should see **2** nodes from `Lucifer-demo-ng` (`desired_size = 2`).

### Next steps

From the main project `README.md`: Argo CD, application manifests, ingress, and cert-manager target this cluster.

---

## 9. Tearing it all down

```bash
terraform destroy
```

EKS teardown can take several minutes. Ensure no critical workloads depend on the cluster.

> **Warning:** SPOT nodes can be terminated by AWS at any time.

---

## 10. AWS resources created (summary)

| Resource | Name / detail | Purpose |
|----------|---------------|---------|
| EKS cluster | `Lucifer-eks-cluster` | Managed Kubernetes control plane |
| Add-ons | CoreDNS, kube-proxy, vpc-cni | Core networking and DNS |
| Node group | `Lucifer-demo-ng` | 2–3 × `t2.large` SPOT, 35 GB disk |
| IAM roles | (via module) | Cluster and node permissions |
| Security groups | (via module) | Control plane ↔ node traffic |
| Data lookup | `aws_instances.eks_nodes` | Running worker instance IPs |

---

## 11. Security reminders before going to production

| Topic | Current setup | Production consideration |
|-------|---------------|---------------------------|
| API endpoint | Public | Restrict `publicAccessCidrs` or use private endpoint |
| Nodes | SPOT `t2.large` in public subnets | On-demand nodes in private subnets + NAT |
| Auth | IAM → kubeconfig | RBAC, IRSA for pods, least-privilege IAM |

---

## 12. Quick reference diagram

```
provider.tf (local.name = Lucifer-eks-cluster)
      │
      ▼
module.vpc (vpc.tf)
      │
      ▼
module.eks (eks.tf)
├── Control plane + add-ons
├── Node group: Lucifer-demo-ng
│   ├── 2× t2.large SPOT (desired)
│   └── scale 2 → 3
└── data.aws_instances.eks_nodes
      │
      ▼
outputs.tf (cluster name, endpoint, node IPs)
```

---

*Read `eks.tf` top to bottom in the same order as the 8 steps above. For networking context, read [vpc.README.md](./vpc.README.md) and [provider.README.md](./provider.README.md) first.*
