#!/bin/sh -x
set -x
TERRAFORM_VERSION=0.12.24
VAULT_VERSION=1.4.2
CONSUL_VERSION=1.7.4
NOMAD_VERSION=0.11.3
CONSUL_TEMPLATE_VERSION=0.25.0
ENVCONSUL_VERSION=0.9.3
DOCKER_COMPOSE_VERSION=1.25.0

# sleep 30
echo "[*] Install base"
sudo apt-get -qq update
sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install jq unzip tree curl vim wget git pv make nginx
sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install dnsutils iputils-ping net-tools netcat resolvconf

echo "[*] Install cloud tools"
sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install awscli
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

echo "[*] Install HashiCorp"
curl -s -o /tmp/vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}+ent/vault_${VAULT_VERSION}+ent_linux_amd64.zip
curl -s -o /tmp/consul.zip https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
curl -s -o /tmp/nomad.zip https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip
curl -s -o /tmp/consul-template.zip https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip
curl -s -o /tmp/envconsul.zip https://releases.hashicorp.com/envconsul/${ENVCONSUL_VERSION}/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip
curl -s -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip

install_from_zip() {
  cd /tmp
  sudo unzip -qqo -d /usr/local/bin "/tmp/${1}.zip" && sudo chmod +x "/usr/local/bin/${1}"
  # rm -rf "${1}.zip"
}

for i in terraform vault consul nomad consul-template envconsul; do
install_from_zip $i
done

terraform -install-autocomplete
vault -autocomplete-install
consul -autocomplete-install
nomad -autocomplete-install
for i in terraform vault consul nomad; do
complete -C /usr/local/bin/$i $i
done



echo "#--> Create folders"
sudo mkdir -p /vault/logs /consul /nomad /terraform
sudo chown -R $USER:$USER /vault /consul /nomad /terraform || true
sudo mkdir -p /etc/nomad.d
sudo chmod a+w /etc/nomad.d
sudo mkdir -p /etc/consul.d
sudo chmod a+w /etc/consul.d
sudo mkdir -p /etc/vault.d /etc/vault
sudo chmod a+w /etc/vault.d /etc/vault


echo "[*] Running build."
# sudo apt-get install -y python-dev python-pip
# sudo pip install ansible

# sudo ansible-playbook base_playbook.yml

#------------------------------------------------------------------------------
# Remove this in the future
#------------------------------------------------------------------------------

echo "[*] Build html"
# sudo mkdir -p /var/www/website
# sudo tee /var/www/html/index.html <<EOF
# <html> <head> <style> body { background-color: yellow; } </style> </head>
# <body> <h1> Hello, World $(hostname)! </h1>
# <p>DB address: ${db_address}</p>
# <p>DB port: ${db_port}</p>
# </body> </html>
# EOF