# EC2 Infrastructure Guide (`ec2.tf`)

This document explains what happens when you run Terraform in this folder, with a focus on `ec2.tf`. It is written for someone reading the project for the first time.

---

## What is this folder for?

The `terraform/` folder defines **AWS infrastructure as code**. Instead of clicking through the AWS Console to create a server, you describe the server in `ec2.tf` and Terraform creates (and can update or destroy) it for you.

In this project, the main goal of `ec2.tf` is to provision a single **EC2 instance** that acts as a **CI/CD and DevOps server** (tagged `Jenkins-Automate`). On first boot, it automatically installs Jenkins, Docker, Trivy, AWS CLI, Helm, and kubectl via `install_tools.sh`.

---

## Files involved

| File | Role |
|------|------|
| `ec2.tf` | Defines the EC2 instance and its dependencies (AMI, SSH key, VPC, security group) |
| `install_tools.sh` | Bootstrap script run once when the instance starts |
| `terra-key` / `terra-key.pub` | SSH key pair you generate locally (not committed to git) |
| `ec2.README.md` | This guide |

---

## Big-picture flow

When you run `terraform apply`, Terraform executes resources in dependency order:

```
1. Look up Ubuntu AMI          (data source)
2. Register SSH public key     (aws_key_pair)
3. Ensure default VPC exists   (aws_default_vpc)
4. Create security group       (aws_security_group)
5. Launch EC2 instance         (aws_instance)
   └── On boot: run install_tools.sh (user_data)
```

After the instance is running, you SSH in with `terra-key` and use Jenkins, Docker, kubectl, etc.

---

## Step-by-step: what `ec2.tf` does

### Step 1 — Find the right operating system image (AMI)

```hcl
data "aws_ami" "os_image" { ... }
```

Terraform does **not** hard-code an AMI ID (which changes by region and over time). Instead it **searches** AWS for:

- The **most recent** Ubuntu **24.04** image
- **amd64** architecture
- **HVM** with **gp3** SSD
- Status **available**

The `owners` field limits the search to Canonical (the official Ubuntu publisher on AWS).

**Why it matters:** Your instance always gets a current, supported Ubuntu image without manual lookup.

---

### Step 2 — Register your SSH public key

```hcl
resource "aws_key_pair" "deployer" {
  key_name   = "terra-automate-key"
  public_key = file("terra-key.pub")
}
```

Before Terraform runs, you create a key pair locally:

```bash
ssh-keygen -f terra-key
```

Terraform uploads **only the public key** (`terra-key.pub`) to AWS as `terra-automate-key`. You keep the private key (`terra-key`) on your machine to SSH into the server.

**Why it matters:** AWS needs a registered key so you can log in as the `ubuntu` user without a password.

---

### Step 3 — Use the default VPC

```hcl
resource "aws_default_vpc" "default" { }
```

Each AWS account has a **default VPC** per region. This resource makes sure Terraform can reference it (for the security group and networking).

**Why it matters:** The EC2 instance needs a network. The default VPC is the simplest option for learning and small setups.

---

### Step 4 — Create a security group (firewall rules)

```hcl
resource "aws_security_group" "allow_user_to_connect" { ... }
```

A security group controls **inbound** and **outbound** traffic to the instance.

| Direction | Ports | Purpose |
|-----------|-------|---------|
| Inbound | 22 | SSH — connect to the server |
| Inbound | 80 | HTTP — web traffic |
| Inbound | 443 | HTTPS — secure web traffic |
| Inbound | 8080 | Jenkins default port |
| Outbound | All | Instance can reach the internet (updates, downloads, AWS API) |

`cidr_blocks = ["0.0.0.0/0"]` means **any IP on the internet** can reach these ports. That is convenient for demos and learning but **not ideal for production** — you would normally restrict SSH to your own IP.

**Why it matters:** Without these rules, you could not SSH in or reach Jenkins in the browser.

---

### Step 5 — Launch the EC2 instance

```hcl
resource "aws_instance" "testinstance" { ... }
```

This is the actual virtual server. Important settings:

| Setting | Value | Meaning |
|---------|--------|---------|
| `ami` | From Step 1 | Ubuntu 24.04 |
| `instance_type` | `var.instance_type` | Size/CPU/RAM (e.g. `t2.micro`, `t3.medium`) — you pass this when running Terraform |
| `key_name` | `terra-automate-key` | SSH key from Step 2 |
| `security_groups` | `allow_user_to_connect` | Firewall from Step 4 |
| `user_data` | `install_tools.sh` | Script run on **first boot only** |
| `root_block_device` | 20 GB `gp3` | Disk size and type |
| `tags.Name` | `Jenkins-Automate` | Friendly name in AWS Console |

**Why it matters:** This block ties together AMI, keys, networking, disk, and bootstrap automation into one server.

---

## What `install_tools.sh` does on first boot

When the instance starts, AWS runs `install_tools.sh` as **user data**. The script:

1. Updates Ubuntu packages
2. Installs **OpenJDK 17** (required by Jenkins)
3. Installs and starts **Jenkins** (enabled on boot)
4. Installs **Docker** and adds `jenkins` and your user to the `docker` group
5. Installs **Trivy** (container/image vulnerability scanner)
6. Installs **AWS CLI**, **Helm**, and **kubectl** via snap

After a few minutes, the machine is ready to run pipelines, build containers, and talk to Kubernetes/EKS.

> **Note:** User data runs only on the **first** launch. If you change `install_tools.sh` later, you typically need a new instance or run the script manually on the existing one.

---

## Prerequisites (before `terraform apply`)

1. **AWS account** with credentials configured (`aws configure` or environment variables)
2. **Terraform** installed on your machine
3. **SSH key pair** in the `terraform/` directory:
   ```bash
   cd terraform
   ssh-keygen -f terra-key
   chmod 400 terra-key
   ```
4. **`instance_type` variable** — `ec2.tf` uses `var.instance_type`. Define it in a `variables.tf` file or pass it on the command line, for example:
   ```bash
   terraform apply -var="instance_type=t3.medium"
   ```

---

## How to run it (typical workflow)

```bash
cd terraform

# 1. Download providers and initialize backend
terraform init

# 2. Preview what will be created
terraform plan -var="instance_type=t3.medium"

# 3. Create infrastructure
terraform apply -var="instance_type=t3.medium"
```

Confirm with `yes` when prompted.

---

## After deployment

1. Open the **AWS EC2 Console** → find instance **Jenkins-Automate**
2. Copy its **public IPv4 address**
3. SSH in:
   ```bash
   ssh -i terra-key ubuntu@<public-ip>
   ```
4. Jenkins (once install finishes) is usually at:
   ```text
   http://<public-ip>:8080
   ```
5. Initial Jenkins admin password (on the server):
   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```

From there you can configure Jenkins pipelines for this e-commerce app, use Docker to build images, and use kubectl/Helm against your EKS cluster (see the main project `README.md` for EKS/kubeconfig steps).

---

## What Terraform creates (summary)

| AWS resource | Name / identifier | Purpose |
|--------------|-------------------|---------|
| Key pair | `terra-automate-key` | SSH access |
| Default VPC | (account default) | Networking |
| Security group | `allow TLS` / tag `mysecurity` | Firewall |
| EC2 instance | `Jenkins-Automate` | DevOps / Jenkins server |

---

## Destroying infrastructure

To tear everything down and avoid ongoing charges:

```bash
terraform destroy -var="instance_type=t3.medium"
```

This removes the resources Terraform created. It does **not** delete your local `terra-key` files.

---

## Security reminders for production

- Restrict SSH (port 22) to your IP instead of `0.0.0.0/0`
- Put Jenkins behind HTTPS and authentication; do not leave port 8080 open to the world long term
- Never commit `terra-key` or AWS secrets to git (they are in `.gitignore`)
- Use IAM roles attached to the instance instead of long-lived access keys where possible

---

## Quick reference diagram

```text
Your laptop                         AWS (your region)
───────────                         ─────────────────

terra-key (private)  ──SSH:22──►   EC2: Jenkins-Automate
terra-key.pub        ──upload──►   Key pair: terra-automate-key
                                   │
terraform apply      ──creates──►   Security group (22,80,443,8080)
                                   │
install_tools.sh     ──user_data►  Jenkins + Docker + Trivy + CLI tools
```

If you are new to Terraform, read `ec2.tf` top to bottom in the same order as the steps above — each block builds on the previous one until the server is running and configured.
