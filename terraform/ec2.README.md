# EC2 Infrastructure Guide — `ec2.tf`

> **Who is this for?** Anyone new to Terraform or AWS who wants to understand exactly what this project does, step by step, before running a single command.

---

## Table of Contents

1. [What does this project do?](#1-what-does-this-project-do)
2. [Files in this folder](#2-files-in-this-folder)
3. [Prerequisites — do these before anything else](#3-prerequisites--do-these-before-anything-else)
4. [How Terraform works (quick mental model)](#4-how-terraform-works-quick-mental-model)
5. [What ec2.tf does — step by step](#5-what-ec2tf-does--step-by-step)
   - [Step 1 — Find the right server image (AMI)](#step-1--find-the-right-server-image-ami)
   - [Step 2 — Register your SSH key with AWS](#step-2--register-your-ssh-key-with-aws)
   - [Step 3 — Use the default network (VPC)](#step-3--use-the-default-network-vpc)
   - [Step 4 — Create firewall rules (Security Group)](#step-4--create-firewall-rules-security-group)
   - [Step 5 — Launch the EC2 server](#step-5--launch-the-ec2-server)
6. [What happens on first boot — install_tools.sh](#6-what-happens-on-first-boot--install_toolssh)
7. [Running Terraform — the full workflow](#7-running-terraform--the-full-workflow)
8. [After deployment — connect and use Jenkins](#8-after-deployment--connect-and-use-jenkins)
9. [Tearing it all down](#9-tearing-it-all-down)
10. [AWS resources created (summary)](#10-aws-resources-created-summary)
11. [Security reminders before going to production](#11-security-reminders-before-going-to-production)
12. [Quick reference diagram](#12-quick-reference-diagram)

---

## 1. What does this project do?

The `terraform/` folder provisions a single **AWS EC2 virtual server** automatically using code instead of clicking through the AWS console. The server is tagged `Jenkins-Automate` and is pre-configured as a **CI/CD and DevOps machine**.

On its very first boot, the server installs:

| Tool | Why it's needed |
|------|-----------------|
| Jenkins | Runs your CI/CD pipelines |
| Docker | Builds and runs containers |
| Trivy | Scans container images for vulnerabilities |
| AWS CLI | Talks to AWS services from the terminal |
| Helm | Deploys apps to Kubernetes |
| kubectl | Controls the Kubernetes (EKS) cluster `Lucifer-eks-cluster` |

You write the infrastructure once in `ec2.tf`, run three commands, and AWS creates it all for you.

---

## 2. Files in this folder

```
terraform/
├── provider.tf         ← AWS provider, region, shared locals (see provider.README.md)
├── variables.tf        ← Input variables (see variables.README.md)
├── vpc.tf              ← VPC for EKS (see vpc.README.md)
├── eks.tf              ← EKS cluster Lucifer-eks-cluster (see eks.README.md)
├── ec2.tf              ← This file: Jenkins/DevOps EC2 server
├── outputs.tf          ← Values printed after apply (see outputs.README.md)
├── install_tools.sh    ← Script that runs automatically on first boot
├── terra-key           ← YOUR private SSH key (you generate this; never commit it)
├── terra-key.pub       ← Public SSH key uploaded to AWS
├── README.md           ← Folder overview and quick start
└── ec2.README.md       ← This guide
```

> `terra-key` and `terra-key.pub` are **not** included in the repo. You generate them yourself in Step 3.

---

## 3. Prerequisites — do these before anything else

Complete these four steps on your local machine **before** running `terraform apply`.

### 3.1 — AWS account and credentials

Make sure you have an AWS account and your credentials are configured:

```bash
aws configure
```

You'll be prompted for:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g. `us-east-1`)
- Default output format (just press Enter for `json`)

### 3.2 — Terraform installed

Download and install Terraform from [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads).

Verify it works:

```bash
terraform -version
```

### 3.3 — Generate your SSH key pair

This creates two files: a private key you keep (`terra-key`) and a public key Terraform uploads to AWS (`terra-key.pub`).

```bash
# Run from inside the terraform/ directory
cd terraform
ssh-keygen -f terra-key
```

When prompted for a passphrase, you can press Enter to skip (fine for learning). Then lock down the private key so only you can read it:

```bash
chmod 400 terra-key
```

> **Never commit `terra-key` to git.** It's your password to the server. It should already be in `.gitignore`.

### 3.4 — Know your instance type

`ec2.tf` uses `var.instance_type` — a variable you pass when running Terraform. Common choices:

| Instance type | vCPUs | RAM | Good for |
|---------------|-------|-----|----------|
| `t2.micro` | 1 | 1 GB | AWS Free Tier only |
| `t3.medium` | 2 | 4 GB | Recommended for Jenkins |
| `t3.large` | 2 | 8 GB | Heavier workloads |

---

## 4. How Terraform works (quick mental model)

Think of Terraform like a shopping list for AWS:

1. You describe what you want in `.tf` files ("I want a server with this size, this OS, this firewall…")
2. `terraform plan` shows you exactly what it will create — **no changes yet**
3. `terraform apply` sends the order to AWS and AWS builds it
4. `terraform destroy` tears it all down when you're done

Terraform figures out the correct **order** to create resources automatically — you don't have to worry about which thing to create first.

---

## 5. What `ec2.tf` does — step by step

Terraform creates resources in this order when you run `apply`:

```
Step 1 → Find Ubuntu AMI
Step 2 → Register SSH public key
Step 3 → Reference default VPC (network)
Step 4 → Create security group (firewall)
Step 5 → Launch EC2 instance (server)
           └─ On first boot: run install_tools.sh
```

---

### Step 1 — Find the right server image (AMI)

```hcl
data "aws_ami" "os_image" {
  owners      = ["<canonical-account-id>"]
  most_recent = true
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/*24.04-amd64*"]
  }
}
```

**What is an AMI?**
An AMI (Amazon Machine Image) is a snapshot of an operating system — think of it as the installer disc for your server. AWS has thousands of them.

**What this block does:**
Instead of hard-coding an AMI ID (which changes by region and gets outdated), Terraform *searches* AWS for:

- The **most recent** Ubuntu **24.04** image
- **64-bit (amd64)** architecture
- **SSD storage (gp3)**
- Only from **Canonical** (the official Ubuntu publisher)

**Why this matters:** You always get a current, supported Ubuntu image without having to look it up manually every time.

---

### Step 2 — Register your SSH key with AWS

```hcl
resource "aws_key_pair" "deployer" {
  key_name   = "terra-automate-key"
  public_key = file("terra-key.pub")
}
```

**What is SSH key-based login?**
Instead of a username/password, AWS uses a key pair to let you into the server. You have:
- A **private key** (`terra-key`) on your laptop — like a physical key
- A **public key** (`terra-key.pub`) uploaded to AWS — like the lock on the door

**What this block does:**
Terraform reads `terra-key.pub` and registers it in AWS under the name `terra-automate-key`. The private key never leaves your machine.

**Why this matters:** Without this, you can't SSH into the server once it's running.

---

### Step 3 — Use the default network (VPC)

```hcl
resource "aws_default_vpc" "default" {}
```

**What is a VPC?**
A VPC (Virtual Private Cloud) is your private network inside AWS — like a walled section of the internet that belongs to your account.

**What this block does:**
Every AWS account comes with a default VPC already set up. This one-liner tells Terraform "just use that existing default VPC" so the security group and EC2 instance have a network to attach to.

**Why this matters:** EC2 instances must live inside a VPC. This is the simplest option and requires no configuration.

---

### Step 4 — Create firewall rules (Security Group)

```hcl
resource "aws_security_group" "allow_user_to_connect" {
  name   = "allow TLS"
  vpc_id = aws_default_vpc.default.id

  # --- Inbound rules (who can reach the server) ---

  ingress { from_port = 22,   to_port = 22,   protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }  # SSH
  ingress { from_port = 80,   to_port = 80,   protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }  # HTTP
  ingress { from_port = 443,  to_port = 443,  protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }  # HTTPS
  ingress { from_port = 8080, to_port = 8080, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }  # Jenkins

  # --- Outbound rule (what the server can reach) ---

  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }         # All traffic
}
```

**What is a Security Group?**
It's a firewall that sits in front of your EC2 instance. You define rules for what traffic is allowed in (ingress) and out (egress).

**Port breakdown:**

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH — log into the server from your terminal |
| 80 | TCP | HTTP — plain web traffic |
| 443 | TCP | HTTPS — encrypted web traffic |
| 8080 | TCP | Jenkins dashboard in your browser |
| All | All | Outbound — server can reach the internet for updates/downloads |

**What `0.0.0.0/0` means:**
This means "allow any IP address." It's fine for learning but you'd restrict port 22 to your own IP in a real production environment.

**Why this matters:** Without these rules, you can't SSH in, and you can't open Jenkins in your browser.

---

### Step 5 — Launch the EC2 server

```hcl
resource "aws_instance" "testinstance" {
  ami             = data.aws_ami.os_image.id     # Ubuntu 24.04 from Step 1
  instance_type   = var.instance_type            # e.g. t3.medium — you pass this
  key_name        = aws_key_pair.deployer.key_name  # SSH key from Step 2
  security_groups = [aws_security_group.allow_user_to_connect.name]  # Firewall from Step 4
  user_data       = file("${path.module}/install_tools.sh")  # Bootstrap script (runs once on boot)

  root_block_device {
    volume_size = 20        # 20 GB disk
    volume_type = "gp3"     # Modern SSD type
  }

  tags = {
    Name = "Jenkins-Automate"   # Friendly name shown in the AWS console
  }
}
```

**What is an EC2 instance?**
It's a virtual machine running in AWS — your actual server. You pick the OS (AMI), size (instance type), networking, storage, and startup script.

**What this block ties together:**

| Setting | Value | What it does |
|---------|-------|--------------|
| `ami` | From Step 1 | Boots Ubuntu 24.04 |
| `instance_type` | e.g. `t3.medium` | Sets CPU and RAM |
| `key_name` | `terra-automate-key` | Lets you SSH in |
| `security_groups` | From Step 4 | Applies the firewall |
| `user_data` | `install_tools.sh` | Runs automatically on first boot |
| `volume_size` | 20 GB | How much disk space the server has |
| `Name` tag | `Jenkins-Automate` | What you see in the AWS console |

**Why this matters:** This is the actual server. Everything above was just preparation — this block creates the machine.

---

## 6. What happens on first boot — `install_tools.sh`

When the EC2 instance starts for the **first time**, AWS automatically runs `install_tools.sh` as root. The script does the following in order:

```
1. apt update          → Refresh Ubuntu's package list
2. Install OpenJDK 17  → Java runtime that Jenkins requires
3. Install Jenkins     → The CI/CD server; started and enabled on boot
4. Install Docker      → Container engine; adds jenkins user to docker group
5. Install Trivy       → Vulnerability scanner for container images
6. Install AWS CLI     → Lets the server talk to AWS services
7. Install Helm        → Kubernetes package manager (via snap)
8. Install kubectl     → Kubernetes CLI (via snap)
```

**Important:** `user_data` only runs **once** — on the very first boot. If you later change `install_tools.sh` and run `terraform apply` again, the existing server won't re-run it. You'd need to SSH in and run the script manually, or destroy and re-create the instance.

Allow **3–5 minutes** after the instance starts for all tools to finish installing.

---

## 7. Running Terraform — the full workflow

Run these commands from inside the `terraform/` directory.

### Step 1 — Initialize Terraform

Downloads the AWS provider plugin that Terraform needs. Only required once per project (or after a provider change).

```bash
terraform init
```

### Step 2 — Preview what will be created

Shows you exactly what Terraform will create, change, or destroy — **no changes are made at this point.** Always read this before applying.

```bash
terraform plan -var="instance_type=t3.medium"
```

You'll see a list of resources to be created, something like:
```
+ aws_key_pair.deployer
+ aws_default_vpc.default
+ aws_security_group.allow_user_to_connect
+ aws_instance.testinstance
```

### Step 3 — Create the infrastructure

Actually creates the resources in AWS. You'll be asked to type `yes` to confirm.

```bash
terraform apply -var="instance_type=t3.medium"
```

When it finishes, your server is running in AWS.

---

## 8. After deployment — connect and use Jenkins

### Find the server's IP address

Open the [AWS EC2 Console](https://console.aws.amazon.com/ec2), go to **Instances**, and find `Jenkins-Automate`. Copy its **Public IPv4 address**.

### SSH into the server

```bash
ssh -i terra-key ubuntu@<your-public-ip>
```

Replace `<your-public-ip>` with the IP from above. The `-i terra-key` flag tells SSH to use your private key.

If you get a "Permission denied" error, make sure you ran `chmod 400 terra-key` earlier.

### Open Jenkins in your browser

Wait 3–5 minutes after the instance starts, then visit:

```
http://<your-public-ip>:8080
```

### Get the Jenkins initial admin password

Jenkins generates a one-time setup password on first start. Retrieve it by SSHing into the server and running:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Copy and paste this password into the Jenkins setup screen in your browser to complete the initial configuration.

---

## 9. Tearing it all down

When you're done and want to stop incurring AWS charges, destroy everything Terraform created:

```bash
terraform destroy -var="instance_type=t3.medium"
```

Type `yes` when prompted. This removes the EC2 instance, security group, key pair, and VPC reference from your account.

> Your local `terra-key` and `terra-key.pub` files are **not** deleted — they stay on your machine.

---

## 10. AWS resources created (summary)

| Resource type | Name / Identifier | What it does |
|---------------|-------------------|--------------|
| `aws_key_pair` | `terra-automate-key` | SSH access to the server |
| `aws_default_vpc` | (account's default) | Network for the server |
| `aws_security_group` | `allow TLS` / tag `mysecurity` | Firewall rules |
| `aws_instance` | `Jenkins-Automate` | The DevOps/Jenkins server |

---

## 11. Security reminders before going to production

The current setup is fine for learning. Before using this in a real environment:

- **Restrict SSH (port 22)** — Change `0.0.0.0/0` to your own IP address to prevent the whole internet from attempting to log in
- **Don't expose Jenkins directly** — Put it behind HTTPS with a real domain name and require authentication; don't leave port 8080 open long-term
- **Never commit `terra-key`** — It's your server's private key. It's in `.gitignore` but double-check it never ends up in git
- **Use IAM roles, not static keys** — Attach an IAM role to the EC2 instance instead of storing AWS access keys on the server

---

## 12. Quick reference diagram

```
Your laptop                              AWS (your chosen region)
───────────────────                      ──────────────────────────────────────

terra-key.pub  ──── Terraform uploads ──► Key pair: terra-automate-key
                                                │
terraform apply ─── creates ────────────► Security group (ports 22, 80, 443, 8080)
                                                │
install_tools.sh ── user_data ──────────► EC2: Jenkins-Automate (Ubuntu 24.04)
                                                │
                                         Boots and auto-installs:
                                         Jenkins · Docker · Trivy
                                         AWS CLI · Helm · kubectl

terra-key (private) ─── SSH port 22 ───► ubuntu@<public-ip>

Browser ─────────────── port 8080 ──────► http://<public-ip>:8080  (Jenkins)
```

---

*If you're brand new to Terraform, read `ec2.tf` from top to bottom in the same order as the 5 steps above — each block builds on the previous one until the server is running and fully configured.*