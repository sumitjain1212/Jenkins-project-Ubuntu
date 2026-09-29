#!/bin/bash
# EC2 User Data: install SonarQube Community Build on Ubuntu 24.04
# Needs: t3.medium or larger (4 GB+ RAM), security group with TCP 9000 open.
# Logs: /var/log/cloud-init-output.log
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Change this to the latest version from https://www.sonarsource.com/products/sonarqube/downloads/
SONAR_VERSION="26.7.0.124771"
DB_PASSWORD="$(openssl rand -hex 16)"

# 1. Kernel settings required by SonarQube's embedded Elasticsearch
cat > /etc/sysctl.d/99-sonarqube.conf <<EOF
vm.max_map_count=524288
fs.file-max=131072
EOF
sysctl --system

# 2. Java 21 + PostgreSQL + tools
apt-get update -y
apt-get install -y openjdk-21-jdk postgresql postgresql-contrib unzip wget
systemctl enable --now postgresql

# 3. Database and user
sudo -u postgres psql <<EOF
CREATE USER sonarqube WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';
CREATE DATABASE sonarqube OWNER sonarqube;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonarqube;
EOF

# 4. Download and unpack SonarQube
cd /tmp
wget -q "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONAR_VERSION}.zip"
unzip -q "sonarqube-${SONAR_VERSION}.zip" -d /opt
mv "/opt/sonarqube-${SONAR_VERSION}" /opt/sonarqube
rm -f "sonarqube-${SONAR_VERSION}.zip"

# 5. Dedicated user (SonarQube will not run as root)
useradd -r -s /bin/false sonarqube || true
cat >> /opt/sonarqube/conf/sonar.properties <<EOF
sonar.jdbc.username=sonarqube
sonar.jdbc.password=${DB_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
EOF
chown -R sonarqube:sonarqube /opt/sonarqube

# 6. systemd service (pick the right binary folder for x86 vs Graviton)
case "$(uname -m)" in
  x86_64)  SONAR_BIN="linux-x86-64" ;;
  aarch64) SONAR_BIN="linux-aarch-64" ;;
  *) echo "Unsupported architecture"; exit 1 ;;
esac

cat > /etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=SonarQube
After=network.target postgresql.service

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/${SONAR_BIN}/sonar.sh start
ExecStop=/opt/sonarqube/bin/${SONAR_BIN}/sonar.sh stop
User=sonarqube
Group=sonarqube
Restart=on-failure
LimitNOFILE=131072
LimitNPROC=8192

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sonarqube

# 7. Wait until SonarQube reports UP (can take a few minutes)
for i in $(seq 1 60); do
  if curl -s http://127.0.0.1:9000/api/system/status | grep -q '"status":"UP"'; then
    echo "SonarQube is UP on port 9000 (default login: admin / admin)"
    exit 0
  fi
  sleep 10
done
echo "SonarQube not UP yet, check /opt/sonarqube/logs/sonar.log and es.log"
