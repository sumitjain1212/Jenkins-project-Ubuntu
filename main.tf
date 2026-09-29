terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

############################
# Variables
############################
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ami_id" {
  type    = string
  default = "ami-0b6d9d3d33ba97d99"
}

# Existing EC2 key pair named "Login" (the file you keep locally is Login.pem)
variable "key_name" {
  type    = string
  default = "Login"
}

# Instance types. Defaults are Free Tier eligible for accounts created on/after 15 Jul 2025.
# Check yours with:
#   aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true \
#     --query "InstanceTypes[*].[InstanceType]" --output text | sort
variable "sonarqube_instance_type" {
  type    = string
  default = "c7i-flex.large" # 2 vCPU / 4 GB RAM (SonarQube needs 4 GB+)
}

variable "nexus_instance_type" {
  type    = string
  default = "c7i-flex.large" # 2 vCPU / 4 GB RAM
}

variable "test_instance_type" {
  type    = string
  default = "t3.small"
}

# Optional: let Terraform SSH in and wait until each install finishes.
# Needs the runner (e.g. Jenkins) to be allowed on port 22 and to have the .pem file.
variable "wait_for_install" {
  type    = bool
  default = false
}

# Path to Login.pem on the machine running Terraform (only read when wait_for_install = true)
variable "private_key_path" {
  type    = string
  default = "Login.pem"
}

# Restrict this to your own IP, e.g. "203.0.113.10/32"
variable "allowed_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

############################
# Default VPC
############################
data "aws_vpc" "default" {
  default = true
}

############################
# Security groups
############################
resource "aws_security_group" "sonarqube" {
  name        = "sonarqube-sg"
  description = "SonarQube server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "SonarQube UI"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sonarqube-sg" }
}

resource "aws_security_group" "nexus" {
  name        = "nexus-sg"
  description = "Nexus server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "Nexus UI"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "nexus-sg" }
}

resource "aws_security_group" "test" {
  name        = "test-sg"
  description = "Test server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "test-sg" }
}

############################
# EC2 instances
############################
resource "aws_instance" "sonarqube" {
  ami                         = var.ami_id
  instance_type               = var.sonarqube_instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sonarqube.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/scripts/sonarqube.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "SonarQubeServer" }
}

resource "aws_instance" "nexus" {
  ami                         = var.ami_id
  instance_type               = var.nexus_instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.nexus.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/scripts/nexus.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "NexusServer" }
}

resource "aws_instance" "test" {
  ami                         = var.ami_id
  instance_type               = var.test_instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.test.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/scripts/testserver.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "TestServer" }
}

############################
# Optional: wait for installs to finish (only when wait_for_install = true)
############################
resource "terraform_data" "wait_sonarqube" {
  count = var.wait_for_install ? 1 : 0

  connection {
    type        = "ssh"
    host        = aws_instance.sonarqube.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "curl -s http://127.0.0.1:9000/api/system/status",
    ]
  }
}

resource "terraform_data" "wait_nexus" {
  count = var.wait_for_install ? 1 : 0

  connection {
    type        = "ssh"
    host        = aws_instance.nexus.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "curl -s -o /dev/null -w 'Nexus HTTP status: %%{http_code}\\n' http://127.0.0.1:8081/",
    ]
  }
}

resource "terraform_data" "wait_test" {
  count = var.wait_for_install ? 1 : 0

  connection {
    type        = "ssh"
    host        = aws_instance.test.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "terraform -version",
    ]
  }
}

############################
# Outputs
############################
output "sonarqube_url" {
  value = "http://${aws_instance.sonarqube.public_ip}:9000"
}

output "nexus_url" {
  value = "http://${aws_instance.nexus.public_ip}:8081"
}

output "test_server_ip" {
  value = aws_instance.test.public_ip
}

output "ssh_commands" {
  value = {
    sonarqube = "ssh -i Login.pem ubuntu@${aws_instance.sonarqube.public_ip}"
    nexus     = "ssh -i Login.pem ubuntu@${aws_instance.nexus.public_ip}"
    test      = "ssh -i Login.pem ubuntu@${aws_instance.test.public_ip}"
  }
}
