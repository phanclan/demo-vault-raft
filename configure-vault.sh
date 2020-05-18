#!/bin/bash
set -ex
echo "#==> Start Kill Vault"
sudo systemctl stop vault || true
sudo killall vault || true
rm -rf /tmp/vault || true
echo "#==> End Kill Vault"

echo -e '\e[38;5;198m'"#==> Create Vault service file at /etc/systemd/system/vault.service\e[0m"
# sudo tee /etc/systemd/system/vault.service > /dev/null <<"EOF"
# [Unit]
# Description="HashiCorp Vault - A tool for managing secrets"
# Documentation=https://www.vaultproject.io/docs/
# Requires=network-online.target
# After=network-online.target
# ConditionFileNotEmpty=/etc/vault.d/vault.hcl
# StartLimitIntervalSec=60
# StartLimitBurst=3

# [Service]
# # User=vault
# # Group=vault
# ProtectSystem=full
# ProtectHome=read-only
# PrivateTmp=yes
# PrivateDevices=yes
# SecureBits=keep-caps
# AmbientCapabilities=CAP_IPC_LOCK
# Capabilities=CAP_IPC_LOCK+ep
# CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
# NoNewPrivileges=yes
# ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
# ExecReload=/bin/kill --signal HUP $MAINPID
# KillMode=process
# KillSignal=SIGINT
# Restart=on-failure
# RestartSec=5
# TimeoutStopSec=30
# StartLimitInterval=60
# StartLimitIntervalSec=60
# StartLimitBurst=3
# LimitNOFILE=65536
# LimitMEMLOCK=infinity

# [Install]
# WantedBy=multi-user.target
# EOF

echo "#==> WRITE VAULT CONFIGURATION"
sudo mkdir -p /etc/vault.d
IP_ADDRESS=$(ifconfig eth1 | grep inet | grep -v inet6 | awk '{print $2}')
sudo tee /etc/vault.d/vault.hcl > /dev/null <<EOF
# storage "file" {
#   path = "/tmp/vault/server"
# }
storage "raft" {
  path    = "/tmp/vault/server"
  node_id = "$(hostname)"
  retry_join {
    leader_api_addr = "http://192.168.50.101:8200"
  }
  retry_join {
    leader_api_addr = "http://192.168.50.102:8200"
  }
  retry_join {
    leader_api_addr = "http://192.168.50.103:8200"
  }
}
# storage "consul" {
#   path = "vault/"
# }
listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = "true"
}
api_addr = "http://${IP_ADDRESS}:8200"
# cluster_addr is required for raft.
cluster_addr = "http://${IP_ADDRESS}:8201"
disable_mlock = true
ui = true
telemetry {
  dogstatsd_addr = "127.0.0.1:8125"
  disable_hostname = true
}
#--> Need auto-unseal?
# seal "awskms" {
#   region = "us-west-2"
#   kms_key_id = "8f101e5a-cd44-4225-bf26-270b203e4f55"
# }
# seal "transit" {
#   address = "https://vault-core:8200"
#   token = "s.w7Mz8ww7tucvAac4ADqPc1Ml"
#   disable_renewal = false

#   // Key configuration
#   key_name = "<transit_key_name>"
#   mount_path = "<transit_mount_path>/"
#   namespace = "<namespace>/"

#   //TLS Configuration
# }
EOF

# read -p "Press any key to resume ..."

echo "--> Generate systemd configuration"
sudo tee /etc/systemd/system/vault.service > /dev/null <<"EOF"
[Unit]
Description=Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

[Service]
Restart=on-failure
ExecStart=/usr/local/bin/vault server -config="/etc/vault.d/vault.hcl"
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

# read -p "Press any key to resume ..."

echo -e '\e[38;5;82m'"#==> Enable Vault service and start Vault"'\e[0m'
mkdir -p /tmp/vault/server
sudo chown -R $USER:$USER /tmp/vault
sudo systemctl daemon-reload
sudo systemctl enable --now vault
echo "#==> check vault service status [pp] removed; caused script to lock up"
# sudo systemctl status vault

# read -p "Press any key to resume ..."

echo -e '\e[38;5;82m'"--> Write Vault profile"'\e[0m'
sudo tee /etc/profile.d/vault.sh > /dev/null <<"EOF"
alias vualt="vault"
# export VAULT_ADDR="http://active.vault.service.consul:8200"
export VAULT_ADDR="http://127.0.0.1:8200"
export CONSUL_HTTP_ADDR="http://127.0.0.1:8500"
EOF
source /etc/profile.d/vault.sh


#------------------------------------------------------------------------------

if [ $HOSTNAME = "server-a-1" ]; then

  echo -e '\e[38;5;82m'"#==> Initialize Vault server\e[0m"
  # read -p "Press any key to resume ..."

  export VAULT_ADDR=http://127.0.0.1:8200
  echo "export VAULT_ADDR=http://127.0.0.1:8200" >> ~/.bashrc

  # start initialization with the default options by running the command below
  # sudo rm -rf /var/lib/vault/data/*
  sleep 5
  vault operator init > /tmp/vault/vault.init
  mkdir -p /vagrant/tmp/
  cp /tmp/vault/vault.init /vagrant/tmp/vault.init

  echo -e '\e[38;5;92m'"++++ Auto unseal vault"'\e[0m'
  for i in $(cat /tmp/vault/vault.init | grep Unseal | cut -d " " -f4 | head -n 3); do
  vault operator unseal $i
  done

  # cat /etc/vault/init.file

  echo -e '\e[38;5;198m'"#==> add vault ENV variables"'\e[0m'
  export VAULT_TOKEN=$(grep 'Initial Root Token' /tmp/vault/vault.init | cut -d ':' -f2 | tr -d ' ')

  x=0
  until vault status | grep active; do
  let x+=1
  sleep 2;
  echo ${x}
  done

  vault write sys/license text=@/vagrant/vault.hclic

  echo "#==> Storing secret 'kv/apikey' to demonstrate snapshot and recovery methods"
  vault secrets enable -path=kv kv-v2
  sleep 2s
  vault kv put kv/apikey webapp=ABB39KKPTWOR832JGNLS02
  vault kv get kv/apikey

fi

#------------------------------------------------------------------------------
# Run this at the end
#------------------------------------------------------------------------------
set +x
echo -e '\e[38;5;198m'"Run this command:"'\e[0m'
echo "export VAULT_TOKEN=$(grep 'Initial Root Token' /vagrant/tmp/vault.init | cut -d ':' -f2 | tr -d ' ')"

echo -e '\e[38;5;198m'"Run this command to unseal a-2 and a-3:"'\e[0m'
for i in $(cat /vagrant/tmp/vault.init | grep Unseal | cut -d " " -f4 | head -n 3); do
echo "vault operator unseal $i"
done

