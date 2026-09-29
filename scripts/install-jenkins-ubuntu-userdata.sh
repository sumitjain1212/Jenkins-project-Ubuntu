#!/bin/bash
# EC2 User Data: install Java 21 + Jenkins LTS on Ubuntu Server
# Paste into "Advanced details > User data" when launching the instance.
# User data runs as root, so sudo is not needed.
# Logs: /var/log/cloud-init-output.log
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Install Java FIRST (Jenkins fails to start if Java is missing)
apt-get update -y
apt-get install -y fontconfig openjdk-21-jre wget
java -version

# 2. Add the Jenkins LTS (debian-stable) repository
mkdir -p /etc/apt/keyrings
wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

# 3. Install and start Jenkins
apt-get update -y
apt-get install -y jenkins
systemctl enable --now jenkins

# 4. Print the initial admin password to the cloud-init log
while [ ! -f /var/lib/jenkins/secrets/initialAdminPassword ]; do sleep 5; done
echo "Jenkins initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword
