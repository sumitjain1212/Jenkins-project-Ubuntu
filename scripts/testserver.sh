#!/bin/bash
# EC2 User Data: test server with Terraform, Java, Git and Docker on Ubuntu 24.04
# Logs: /var/log/cloud-init-output.log
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y gnupg software-properties-common curl wget unzip git openjdk-17-jdk docker.io

# Terraform from the official HashiCorp apt repository
wget -qO- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y terraform

systemctl enable --now docker
usermod -aG docker ubuntu || true

terraform -version
echo "Test server ready"
