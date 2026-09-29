#!/bin/bash
# EC2 User Data: install Sonatype Nexus Repository (OSS) on Ubuntu 24.04
# Needs: t3.medium or larger, security group with TCP 8081 open.
# Logs: /var/log/cloud-init-output.log
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Check https://help.sonatype.com/en/download.html for the latest Java 17 build
NEXUS_VERSION="3.70.4-02"

# 1. Java 17 + tools
apt-get update -y
apt-get install -y openjdk-11-jdk wget curl tar

# 2. Download and unpack
cd /tmp
wget -q "https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-java17-unix.tar.gz" -O nexus.tar.gz
tar -xzf nexus.tar.gz -C /opt
mv "/opt/nexus-${NEXUS_VERSION}" /opt/nexus
rm -f nexus.tar.gz

# 3. Dedicated user (Nexus should not run as root)
useradd -r -m -d /opt/nexus-home -s /bin/false nexus || true
chown -R nexus:nexus /opt/nexus /opt/sonatype-work
echo 'run_as_user="nexus"' > /opt/nexus/bin/nexus.rc

# 4. systemd service
cat > /etc/systemd/system/nexus.service <<EOF
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=/opt/nexus/bin/nexus start
ExecStop=/opt/nexus/bin/nexus stop
User=nexus
Group=nexus
Restart=on-abort
TimeoutSec=600

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now nexus

# 5. Wait until Nexus responds (first start can take a few minutes)
for i in $(seq 1 60); do
  if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/ | grep -q '^200$'; then
    echo "Nexus is UP on port 8081"
    echo "Admin password: $(cat /opt/sonatype-work/nexus3/admin.password 2>/dev/null || echo 'not generated yet')"
    exit 0
  fi
  sleep 10
done
echo "Nexus not UP yet, check /opt/sonatype-work/nexus3/log/nexus.log"
