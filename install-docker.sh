#!/bin/bash
set -x

echo "[*] Install docker"
sudo apt-get install -qq apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq docker-ce
sudo service docker restart
sudo usermod -aG docker $USER
sudo usermod -aG docker vagrant || true
sudo usermod -aG docker ubuntu || true

# echo "[*] Install docker-compose"
# sudo curl -sL https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
# sudo chmod +x /usr/local/bin/docker-compose
