# EKS Infrastructure Guide (`eks.tf`)

This document explains what happens when Terraform provisions your **Amazon EKS (Elastic Kubernetes Service)** cluster using `eks.tf`. It is written for someone reading the project for the first time.

For the Jenkins/DevOps EC2 server, see [`ec2.README.md`](./ec2.README.md).

---

## What is this file for?

`eks.tf` does **not** define every low-level AWS resource by hand. Instead, it uses the official **[terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws)** module to create a production-style Kubernetes cluster where this e-commerce app will eventually run (deployed via Jenkins, kubectl, Helm, Argo CD, etc.).

In plain terms:

- **EKS** = managed Kubernetes control plane (AWS runs the masters)
- **Node group** = EC2 workers that run your application pods
- **Add-ons** = core cluster services (DNS, networking proxy, VPC CNI)

The cluster name used in this project is **`tws-eks-cluster`** (via `local.name`).

---

## Files involved

| File | Role |
|------|------|
| `eks.tf` | EKS cluster, add-ons, managed node group, and node discovery |
| `vpc` module (referenced) | Network where the cluster and nodes live — must exist in your Terraform root |
| `locals` (referenced) | Shared values like `local.name` and `local.tags` |
| `ec2.tf` | Separate bastion/Jenkins server (not the EKS workers) |
| `eks.README.md` | This guide |

> **Note:** `eks.tf` depends on `module.vpc` and `local.*` values defined in other `.tf` files in the same `terraform/` directory. When you run `terraform apply`, Terraform wires all `.tf` files together as one configuration.

---

## Big-picture flow

When you run `terraform apply`, the EKS-related work happens roughly in this order:

```
1. VPC already exists          (module.vpc — subnets, routing, etc.)
2. EKS module creates:
   ├── Control plane           (Kubernetes API server)
   ├── Cluster add-ons         (CoreDNS, kube-proxy, vpc-cni)
   ├── IAM roles & policies    (for cluster and nodes)
   └── Managed node group      (tws-demo-ng — worker EC2 instances)
3. Data source looks up        (running EKS worker instances by tag)
```

After the cluster is ready, you connect with:

```bash
aws eks update-kubeconfig --region eu-west-1 --name tws-eks-cluster
kubectl get nodes
```

---

## Step-by-step: what `eks.tf` does

### Step 1 — Call the EKS Terraform module

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.1"
  ...
}
```

Instead of writing dozens of resources yourself, this block pulls a **reusable, community-maintained module** from the Terraform Registry. Version `19.15.1` is pinned so upgrades are intentional.

The module handles the heavy lifting: control plane, node IAM, security groups, and integration with your VPC.

---

### Step 2 — Name the cluster and expose the API

```hcl
cluster_name                   = local.name
cluster_endpoint_public_access = true
```

| Setting | Meaning |
|---------|---------|
| `cluster_name` | Human-readable cluster ID — in this project, `local.name` resolves to **`tws-eks-cluster`** |
| `cluster_endpoint_public_access = true` | The Kubernetes API endpoint is reachable from the public internet (with AWS/IAM auth) |

**Why public access?** Simpler for learning and for tools like Jenkins or a bastion host to run `kubectl` without complex private networking. In production you often restrict this to specific CIDRs or use private-only endpoints.

---

### Step 3 — Install required cluster add-ons

```hcl
cluster_addons = {
  coredns    = { most_recent = true }
  kube-proxy = { most_recent = true }
  vpc-cni    = { most_recent = true }
}
```

These are **essential Kubernetes system components** on EKS:

| Add-on | Purpose |
|--------|---------|
| **vpc-cni** | Assigns real VPC IP addresses to pods (AWS networking model) |
| **kube-proxy** | Network proxy on each node; enables Services to reach pods |
| **coredns** | In-cluster DNS — pods resolve names like `my-service.default.svc.cluster.local` |

`most_recent = true` tells AWS to install the latest compatible version for your cluster.

**Why it matters:** Without these, pods cannot get IPs, services would not route traffic, and DNS inside the cluster would fail.

---

### Step 4 — Attach the cluster to your VPC

```hcl
vpc_id                   = module.vpc.vpc_id
subnet_ids               = module.vpc.public_subnets
control_plane_subnet_ids = module.vpc.intra_subnets
```

| Input | Used for |
|-------|----------|
| `vpc_id` | Which virtual network the cluster belongs to |
| `subnet_ids` (public) | Where **worker nodes** are placed |
| `control_plane_subnet_ids` (intra/private) | Where the **EKS control plane** ENIs are placed |

**Why split subnets?** AWS recommends placing the control plane in dedicated private/intra subnets while workers can live in subnets that meet your routing needs (here, public subnets).

---

### Step 5 — Default settings for all node groups

```hcl
eks_managed_node_group_defaults = {
  instance_types = ["t2.large"]
  attach_cluster_primary_security_group = true
}
```

These defaults apply to every managed node group unless overridden:

- **`t2.large`** — 2 vCPU, 8 GiB RAM per node (burstable)
- **`attach_cluster_primary_security_group`** — Nodes use the cluster’s primary security group for correct control-plane ↔ node communication

---

### Step 6 — Create the managed node group `tws-demo-ng`

```hcl
eks_managed_node_groups = {
  tws-demo-ng = {
    min_size     = 2
    max_size     = 3
    desired_size = 2
    instance_types = ["t2.large"]
    capacity_type  = "SPOT"
    disk_size = 35
    use_custom_launch_template = false
    tags = { ... }
  }
}
```

This is the **worker pool** — actual EC2 machines that run your containers.

| Setting | Value | Meaning |
|---------|--------|---------|
| `min_size` / `max_size` / `desired_size` | 2 / 3 / 2 | Autoscaling: always at least 2 nodes, can scale to 3 |
| `instance_types` | `t2.large` | Instance size for workers |
| `capacity_type` | `SPOT` | Uses **Spot instances** — cheaper, but AWS can reclaim them with short notice |
| `disk_size` | 35 GB | Root volume per node |
| `use_custom_launch_template` | `false` | Lets the module apply `disk_size` directly (comment in code notes this is important) |

**Tags** on the node group:

- `Name = tws-demo-ng`
- `Environment = dev`
- `ExtraTag = e-commerce-app`

**Why SPOT?** Cost savings for dev/demo workloads. Not ideal for critical production without interruption tolerance.

---

### Step 7 — Apply shared tags to the cluster

```hcl
tags = local.tags
```

Project-wide tags (from `local.tags`) are applied to EKS resources for billing, ownership, and filtering in the AWS Console.

---

### Step 8 — Discover running worker instances (data source)

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

This block does **not** create anything. After the cluster exists, Terraform **queries AWS** for EC2 instances tagged with `eks:cluster-name = tws-eks-cluster` that are in `running` state.

**Typical uses:**

- Feed instance IDs into other Terraform resources
- Outputs for automation or documentation
- Ensuring nodes exist before a dependent step runs

`depends_on = [module.eks]` guarantees the lookup runs only after the cluster (and nodes) are created.

---

## How EKS fits in this project

```text
┌─────────────────┐     build/push      ┌──────────────────┐
│  Jenkins EC2    │ ──────────────────► │  Container       │
│  (ec2.tf)       │                     │  Registry (ECR)  │
└────────┬────────┘                     └────────┬─────────┘
         │                                       │
         │  kubectl / helm / argocd              │ pull images
         ▼                                       ▼
┌─────────────────────────────────────────────────────────────┐
│  EKS Cluster (eks.tf) — tws-eks-cluster                     │
│  ┌─────────────┐  ┌─────────────┐                           │
│  │ Node (SPOT) │  │ Node (SPOT) │  ... tws-demo-ng         │
│  └─────────────┘  └─────────────┘                           │
│         Pods: e-commerce app, Argo CD, ingress, etc.        │
└─────────────────────────────────────────────────────────────┘
```

- **`ec2.tf`** — CI/CD tooling (Jenkins, Docker, Trivy, kubectl installed via `install_tools.sh`)
- **`eks.tf`** — Runtime environment where Kubernetes deploys the app

You often SSH to the Jenkins/bastion host, configure AWS CLI, then run:

```bash
aws eks update-kubeconfig --region eu-west-1 --name tws-eks-cluster
kubectl get nodes
kubectl get pods -A
```

---

## Prerequisites (before EKS can apply)

1. **AWS credentials** with permissions for EKS, EC2, IAM, and VPC
2. **Terraform** initialized in `terraform/` (`terraform init` downloads the EKS module)
3. **VPC module** present and applied — `module.vpc` must expose `vpc_id`, `public_subnets`, and `intra_subnets`
4. **`locals`** defining at least `name` (cluster name) and `tags`
5. **Region** — project docs use **`eu-west-1`** (Ireland)

EKS creation typically takes **10–20 minutes** on first apply.

---

## How to run it (with the rest of Terraform)

EKS is applied together with other `.tf` files in this folder:

```bash
cd terraform

terraform init
terraform plan
terraform apply
```

You do not apply `eks.tf` in isolation — Terraform loads every `*.tf` file in the directory.

---

## After deployment

### 1. Update kubeconfig (local machine or bastion)

```bash
aws configure   # if not already done
aws eks update-kubeconfig --region eu-west-1 --name tws-eks-cluster
```

### 2. Verify the cluster

```bash
kubectl cluster-info
kubectl get nodes
```

You should see **2** nodes (matching `desired_size = 2`), named/labeled for the `tws-demo-ng` group.

### 3. Deploy workloads

From the main project `README.md`, next steps include Argo CD, application manifests, ingress, and cert-manager — all targeting this cluster.

---

## What Terraform creates (summary)

| Component | Name / detail | Purpose |
|-----------|---------------|---------|
| EKS cluster | `tws-eks-cluster` | Managed Kubernetes control plane |
| Add-ons | CoreDNS, kube-proxy, vpc-cni | Core cluster networking & DNS |
| Node group | `tws-demo-ng` | 2–3 × `t2.large` SPOT workers, 35 GB disk |
| IAM roles | (via module) | Cluster and node permissions |
| Security groups | (via module) | Control plane ↔ node traffic |
| Data lookup | `aws_instances.eks_nodes` | Finds running worker EC2 instances |

---

## Destroying the cluster

```bash
terraform destroy
```

EKS teardown can take several minutes. Ensure no critical workloads depend on the cluster before destroying.

> **Warning:** Spot nodes can be terminated by AWS at any time. For production, consider `ON_DEMAND` capacity or a mix of on-demand and spot.

---

## Security & cost reminders

| Topic | Current setup | Production consideration |
|-------|---------------|---------------------------|
| API endpoint | Public | Restrict `publicAccessCidrs` or use private endpoint + VPN/bastion |
| Nodes | SPOT `t2.large` | Use on-demand or mixed capacity for stability |
| Subnets | Public for workers | Private subnets + NAT gateway is common for production |
| Auth | AWS IAM → kubeconfig | Add RBAC, IRSA for pods, and least-privilege IAM |

---

## Quick reference diagram

```text
terraform apply
       │
       ▼
 module.vpc ──────────────┐
 (VPC, subnets)           │
       │                  │
       ▼                  ▼
 module.eks ──► EKS Control Plane (tws-eks-cluster)
       │              + add-ons (coredns, kube-proxy, vpc-cni)
       │
       └──► Managed Node Group: tws-demo-ng
                 ├── 2× t2.large SPOT (desired)
                 ├── scale 2 → 3
                 └── 35 GB disk per node
       │
       ▼
 data.aws_instances.eks_nodes ──► list running worker EC2s
```

Read `eks.tf` top to bottom in that order: **module call → cluster config → networking → node defaults → node group → tags → data source**. Each section builds on the VPC and locals defined elsewhere in the same Terraform project.
