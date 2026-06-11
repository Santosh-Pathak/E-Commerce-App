# =============================================================================
# Jenkins / DevOps EC2 instance — CI/CD server (separate from EKS workers)
# Uses the account default VPC, not the custom VPC in vpc.tf
# =============================================================================

# Step 1: Find the latest Ubuntu 24.04 AMI (avoids hard-coding a region-specific AMI ID)
data "aws_ami" "os_image" {
  owners      = ["*************"] # Canonical (official Ubuntu publisher)
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

# Step 2: Upload your SSH public key so you can log in as ubuntu@<public-ip>
resource "aws_key_pair" "deployer" {
  key_name   = "terra-automate-key"
  public_key = file("terra-key.pub") # Generate locally: ssh-keygen -f terra-key
}

# Step 3: Use the account's default VPC for this standalone EC2 instance
resource "aws_default_vpc" "default" {

}

# Step 4: Firewall rules — control inbound and outbound traffic to the server
resource "aws_security_group" "allow_user_to_connect" {
  name        = "allow TLS"
  description = "Allow user to connect"
  vpc_id      = aws_default_vpc.default.id

  # SSH — terminal access
  ingress {
    description = "port 22 allow"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (package updates, Docker pulls, AWS API calls)
  egress {
    description = " allow all outgoing traffic "
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP — web traffic
  ingress {
    description = "port 80 allow"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — secure web traffic
  ingress {
    description = "port 443 allow"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins dashboard
  ingress {
    description = "port 8080 allow"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysecurity"
  }
}

# Step 5: Launch the EC2 instance and bootstrap DevOps tools on first boot
resource "aws_instance" "testinstance" {
  ami           = data.aws_ami.os_image.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.allow_user_to_connect.name]

  # Runs install_tools.sh once on first boot (Jenkins, Docker, Trivy, kubectl, etc.)
  user_data = file("${path.module}/install_tools.sh")

  tags = {
    Name = "Jenkins-Automate"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

}
