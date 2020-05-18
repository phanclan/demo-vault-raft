# Vault HA Cluster with Integrated Storage
[Vault HA Cluster with Integrated Storage | Vault - HashiCorp Learn](https://learn.hashicorp.com/vault/operations/raft-storage)
[Vault Integrated Storage | hashicorp | Katacoda](https://www.katacoda.com/hashicorp/scenarios/vault-raft)

[Vault HA Cluster with Integrated Storage - Setup](bear://x-callback-url/open-note?id=15A10C1F-D8EC-418A-9944-4676AE48BADD-64526-00023CC3447DB4DA&header=Setup)
[Vault HA Cluster with Integrated Storage - Create an HA cluster](bear://x-callback-url/open-note?id=15A10C1F-D8EC-418A-9944-4676AE48BADD-64526-00023CC3447DB4DA&header=Create%20an%20HA%20cluster)
[Vault HA Cluster with Integrated Storage - Join nodes to the cluster](bear://x-callback-url/open-note?id=15A10C1F-D8EC-418A-9944-4676AE48BADD-64526-00023CC3447DB4DA&header=Join%20nodes%20to%20the%20cluster)
[Vault HA Cluster with Integrated Storage - Retry join](bear://x-callback-url/open-note?id=15A10C1F-D8EC-418A-9944-4676AE48BADD-64526-00023CC3447DB4DA&header=Retry%20join)
[Vault HA Cluster with Integrated Storage - Raft snapshots for data recovery](bear://x-callback-url/open-note?id=15A10C1F-D8EC-418A-9944-4676AE48BADD-64526-00023CC3447DB4DA&header=Raft%20snapshots%20for%20data%20recovery)


# Challenge
Vault supports many storage providers to persist its encrypted data (e.g. Consul, MySQL, DynamoDB, etc.). 

These providers require:

* Their own administration; increasing complexity and total administration.
* Provider configuration to allow Vault as a client.
* Vault configuration to connect to the provider as a client.


# Solution
Use Vault's Integrated Storage to persist the encrypted data. 

The [Integrated Storage](https://www.vaultproject.io/docs/configuration/storage/raft.html) has the following benefits:

* Integrated into Vault (reducing total administration)
* All configuration within Vault
* Supports failover and multi-cluster replication
* Eliminates additional network requests
* Performance gains (reduces disk write/read overhead)
* Lowers complexity when diagnosing issues (leading to faster time to recovery)

![](Vault%20HA%20Cluster%20with%20Integrated%20Storage/vault-raft-0.png)


## Prerequisites
This guide requires Vault, sudo access, and additional configuration to create the cluster.

> **Online tutorial:** An interactive tutorial is also available if you do not wish to install a Vault HA cluster locally.  
> https://www.katacoda.com/hashicorp/scenarios/vault-raft  

* You will need to install Vagrant with Virtualbox or Docker Desktop.
* You will need a Vault enterprise license named `vault.hclic` in the `demo-vault-raft` directory.
* Clone the Vault Raft Demo repo.

```
git clone https://github.com/phanclan/demo-vault-raft.git
```

* Go into the `cd demo-vault-raft/Vagrant` directory.

```
cd demo-vault-raft/Vagrant
```

- - - -

# Setup

The `Vagrantfile` is configured to bring up 6 server instances and 2 client instance. For this demo we only need three servers, so we will bring up only three.

- [ ] Spin up three Ubuntu linux instances using Vagrant.

```
vagrant up server-a-1 server-a-2 server-a-3
```

This can take up to 5 minutes. Each instance of Ubuntu will have Terraform, Vault, Consul, and Nomad installed as well as some tools and utilities like cloud tools, docker, etc.

The provisioning scripts configures and starts three Vault servers. Here's a diagram:

- [ ] ::[pp] needs to be updated::

![](Vault%20HA%20Cluster%20with%20Integrated%20Storage/vault-raft-1.png)

* **server-a-1** (`http://192.168.50.101:8200`) is initialized and unsealed. This Vault starts as the cluster leader. An example K/V-V2 secret is created.
* **server-a-2** (`http://192.168.50.102:8200`) is only started. You will join it to the cluster.
* **server-a-3** (`http://192.168.50.103:8200`) is only started. You will join it to the cluster.

* Make the `configure-vault.sh` file executable:

```
chmod +x configure-vault.sh
```

- [ ] Run `configure-vault.sh`. Will create configuration for all Vault servers. Will also initialize **server-a-1**.

```
for i in 1 2 3; do
vagrant ssh server-a-${i} -c "sudo /vagrant/configure-vault.sh"
done
```

👉  Note the commands from the script output. You will need these later.

Sample Output
```
Run this command:
export VAULT_TOKEN=s.POBKfmkSVrvxROuFTLVD79zh
Run this command to unseal a-2 and a-3:
vault operator unseal UxT9QDPxldsbDnlpfVD8Mb7vLEwOlFW5oPvEFMok+2aL
vault operator unseal w/45tJ1xDArSPaJTNLnBi7gFhrXeW3QvOslTp6micFWZ
vault operator unseal OY34RgYoZ29FwSW8GudVfCfc6wLC97KwHA75VNBl+mpF
```

- [ ] Validate that all four Vaults are running, and ONLY **vault_2** is **initialized** and **unsealed**:

```
for i in 1 2 3; do
echo "HOST: 192.168.50.10${i}"
VAULT_ADDR=http://192.168.50.10${i}:8200 vault status | egrep "true|false"
done
```

Sample Output
```
HOST: 192.168.50.101
Initialized     true
Sealed          false
HA Enabled      true
HOST: 192.168.50.102
Initialized        false
Sealed             true
HA Enabled         true
HOST: 192.168.50.103
Initialized        false
Sealed             true
HA Enabled         true
```

- - - -

## Create an HA cluster

Currently **server-a-1** is initialized, unsealed, and has HA enabled. It is the only node in a cluster. The remaining nodes, **server-a-2** and **server-a-3**, have not joined its cluster.

### Examine the leader

Let's discover more about the configuration of **server-a-1** and how it describes the current state of the cluster.

* ::[pp - need to edit this]:: First, examine the **server-a-1** server configuration file (`config-vault_2.hcl`).

```
storage "raft" {
  path    = "/tmp/vault/server"
  node_id = "server-a-1"
}
listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = "true"
}
api_addr = "http://192.168.50.101:8200"
cluster_addr = "http://127.0.0.1:8201"
disable_mlock = true
ui = true
```

To use the integrated storage, the storage stanza is set to `raft`. The path specifies the path where Vault data will be stored (`/tmp/vault/server`).

- [ ] From host system, examine the current raft peer set **server-a-1**.

```
export VAULT_TOKEN=$(grep 'Initial Root Token' ../tmp/vault.init | awk '{print $NF}')

export VAULT_ADDR=http://192.168.50.101:8200
vault operator raft list-peers
```

Sample Output
```
Node          Address                State       Voter
----          -------                -----       -----
server-a-1    192.168.50.101:8201    leader      true
```

The cluster reports that `server-a-1` is the only node and is currently the leader.

Examine **server-a-1** root token.

```
grep 'Initial Root Token' ../tmp/vault.init | awk '{print $NF}'
```

The `configure-vault.sh` script captured the root token of **server-a-1** during its setup and stored it in this file `../tmp/vault.init`. This root token has privileged access to all nodes within the cluster.

- - - -

# Join nodes to the cluster
Add **server-a-2** to the cluster using the `vault operator raft join` command.

- [ ]  Set the `VAULT_ADDR` to **server-a-2** API address. Join **server-a-2** to the **server-a-1** cluster.

```
export VAULT_ADDR="http://192.168.50.102:8200"
vault operator raft join http://192.168.50.101:8200
```

Output
```
Key       Value
---       -----
Joined    true
```

The `http://192.168.50.101:8200` is the **server-a-1** server address which has been already initialized and auto-unsealed. This makes **server-a-1** the **active** node and its storage behaves as the **leader** in this cluster.

- [ ] Unseal **server-a-1**. The commands to run are at the end of the script output.

```
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
```

* Next, configure the Vault CLI to use **server-a-1** root token for requests.

```
export VAULT_TOKEN=$(grep 'Initial Root Token' /tmp/vault/vault.init | awk '{print $NF}')
```

- [ ] Examine the current raft peer set.

```
vault operator raft list-peers
```

Sample Output
```
Node          Address                State       Voter
----          -------                -----       -----
server-a-1    192.168.50.101:8201    leader      true
server-a-2    192.168.50.102:8201    follower    true
```

**server-a-2** is listed as a **follower** node.

* Examine **server-a-2** log file (`vault_3.log`). ::[pp - need to edit]::

```
$ cat vault_3.log
...
2019-11-21T14:36:15.837-0600 [TRACE] core: found new active node information, refreshing
2019-11-21T14:36:15.837-0600 [DEBUG] core: parsing information for new active node: active_cluster_addr=https://127.0.0.2:8201 active_redirect_addr=http://127.0.0.2:8200
2019-11-21T14:36:15.837-0600 [DEBUG] core: refreshing forwarding connection
2019-11-21T14:36:15.837-0600 [DEBUG] core: clearing forwarding clients
2019-11-21T14:36:15.837-0600 [DEBUG] core: done clearing forwarding clients
2019-11-21T14:36:15.837-0600 [DEBUG] core: done refreshing forwarding connection
2019-11-21T14:36:15.838-0600 [DEBUG] core: creating rpc dialer: host=fw-2e732f3f-c586-45ca-9975-66260b0c0d63
2019-11-21T14:36:15.869-0600 [DEBUG] core.cluster-listener: performing client cert lookup
```

The log describes the process of joining the cluster.

- [ ] Finally, verify that you can read the secret at `kv/apikey`. Note: you are seeing this from **server-a-2** as set by `VAULT_ADDR`.

```
vault kv get kv/apikey
```

Sample Output
```
====== Metadata ======
Key              Value
---              -----
created_time     2019-11-22T19:52:29.59021Z
deletion_time    n/a
destroyed        false
version          1

===== Data =====
Key       Value
---       -----
webapp    ABB39KKPTWOR832JGNLS02
```


- - - -

# Retry join
You can use the `vault operator raft join` command to join **server-a-3** to the cluster in the same way you joined **server-a-2** to the cluster. However, if the connection details of all the nodes are known beforehand, you can configure the `retry_join` stanza in the server configuration file to automatically join the cluster.

* ::[pp - need to edit]:: ~~Stop **vault_4**.~~

- [ ] ::[pp - This was predone]:: Modify the server configuration file, `/etc/vault.d/vault.hcl` by adding the `retry_join` block inside the `storage` stanza as follows.

```
storage "raft" {
  path    = "/tmp/vault/server"
  node_id = "$(hostname)"
  retry_join {
    leader_api_addr = "http://192.168.50.101:8200"
  }
  retry_join {
    leader_api_addr = "http://192.168.50.102:8200"
  }
}
```

Since the address of **server-a-1** and **server-a-2** are known, you can predefine the possible cluster leader addresses in the `retry_join` block.

::[pp - need to edit; didn't need to stop, so don't need to start]:: ~~Start **server-a-3**.~~

- [ ] Unseal **server-a-3**. The unseal keys need to be replaced with your own. The configure script output provides you with the values.

```
export VAULT_ADDR=http://192.168.50.103:8200
vault operator unseal JCjUXY82VfRgCpoKNLVzgCxyb1+xZmjIy27G1B/1fUxO
vault operator unseal jSiDZeH9Chq4ujTmvGa82jF5ZjYrZng585tGXDiF44e/
vault operator unseal g9ScBoNPuSe7TRbzPfExg12s6tDg1a2KmawnwoFgWcAd
```

- [ ] List the peers and notice that **server-a-3** is listed as a follower node.

```
vault operator raft list-peers
```

Sample Output
```
Node          Address                State       Voter
----          -------                -----       -----
server-a-1    192.168.50.101:8201    leader      true
server-a-2    192.168.50.102:8201    follower    true
server-a-3    192.168.50.103:8201    follower    true
```

> TIP: `node_id` - sets what you see under **Node**.   
> `cluster_addr` - sets what you see under **Address**.  

- - - -

## Prepare for Raft Snapshot Scenarios

- [ ] Patch the secret at `kv/apikey` from **server-a-3**

```
export VAULT_ADDR=http://192.168.50.103:8200
vault kv patch kv/apikey expiration="365 days"
```

Sample Output
```
Key              Value
---              -----
created_time     2020-05-18T06:27:33.813577573Z
deletion_time    n/a
destroyed        false
version          2
```

- [ ] From **server-a-2**, read the secret again.

```
export VAULT_ADDR=http://192.168.50.102:8200
vault kv get kv/apikey
```

Sample Output
```
====== Metadata ======
Key              Value
---              -----
created_time     2020-05-18T06:27:33.813577573Z
deletion_time    n/a
destroyed        false
version          2

======= Data =======
Key           Value
---           -----
expiration    365 days
webapp        ABB39KKPTWOR832JGNLS02
```

You should see the new `expiration`  key that you entered from **server-a-3**.

- - - -

# Raft snapshots for data recovery

Raft provides an interface to take snapshots of its data. These snapshots can be used later to restore data if ever becomes necessary.

## Take a snapshot

- [ ] Execute the following command to take a snapshot of the data from **server-a-1**.

```
export VAULT_ADDR=http://192.168.50.101:8200
vault operator raft snapshot save ../tmp/demo.snapshot
```

## Simulate loss of data

- [ ] First, verify that a secrets exists at `kv/apikey`.

```
vault kv get kv/apikey
```

- [ ] Next, delete the secrets at `kv/apikey`.

```
vault kv metadata delete kv/apikey
```

- [ ] Finally, verify that the data has been deleted.

```
$ vault kv get kv/apikey
No value found at kv/data/apikey
```

## Restore data from a snapshot

First, recover the data by restoring the data found in `demo.snapshot`.

```
vault operator raft snapshot restore ../tmp/demo.snapshot
```

::[pp - need to edit]:: ~~(Optional) You can tail the server log of the active node (**vault_2**).~~

```
$ tail -f vault_2.log
```

- [ ] Verify that the data has been recovered.

```
vault kv get kv/apikey
```

Sample Output
```
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-02T05:50:39.038931Z
deletion_time    n/a
destroyed        false
version          2

======= Data =======
Key           Value
---           -----
expiration    365 days
webapp        ABB39KKPTWOR832JGNLS02
```

- - - -

## Resign from active duty
Currently, **server-a-1** is the **active** node. Experiment to see what happens if **vault_2** steps down from its active node duty.

* In the terminal where `VAULT_ADDR` is set to `http://192.168.50.101:8200`, execute the `step-down` command.

```
export VAULT_ADDR=http://192.168.50.102:8200
vault operator step-down
```

```
Success! Stepped down: http://127.0.0.2:8200
```

In the terminal where `VAULT_ADDR` is set to `http://192.168.50.102:8200`, examine the raft peer set.

```
export VAULT_ADDR=http://192.168.50.102:8200
vault operator raft list-peers
```

```
Node          Address                State       Voter
----          -------                -----       -----
server-a-1    192.168.50.101:8201    follower    true
server-a-2    192.168.50.102:8201    leader      true
server-a-3    192.168.50.103:8201    follower    true
```

Notice that **server-a-2** is now promoted to be the leader and **server-a-1** became a follower.

- - - -

## Remove a cluster member

THE REST OF THIS IS **WORK IN PROGRESS**!!!

💀 [pp] I have issues with removing cluster members. The cluster will go down. After removing a member I get the following message.

```
$ vault operator raft list-peers
No raft cluster configuration found
```

It may become important to remove nodes from the cluster for maintenance, upgrades, or to preserve compute resources.

- [ ] Remove **server-a-3** from the cluster.

```
vault operator raft remove-peer server-a-3
```

```
Peer removed successfully!
```

- [ ] Verify that **vault_4** has been removed from the cluster by viewing the raft cluster peers.

```
$ vault operator raft list-peers

Node       Address           State       Voter
----       -------           -----       -----
vault_2    127.0.0.2:8201    follower    true
vault_3    127.0.0.3:8201    leader      true
```

### Add vault_4 back to the cluster
This is an **optional** step.

If you wish to add **vault_4** back to the HA cluster, return to the terminal where `VAULT_ADDR` is set to **vault_4** API address (`http://127.0.0.4:8200`), and stop **vault_4**.

```
$ ./cluster.sh stop vault_4
```

Delete the data directory.

```
$ rm -r raft-vault_4
```

Now, create a raft-vault_4 directory again because the raft storage destination must exists before you can start the server.

```
$ mkdir raft-vault_4
```

Start the **vault_4** server.

```
$ ./cluster.sh start vault_4
```

You can again examine the peer set to confirm that **vault_4** successfully joined the cluster as a follower.
```
$ vault operator raft list-peers

Node       Address           State       Voter
----       -------           -----       -----
vault_2    127.0.0.2:8201    follower    true
vault_3    127.0.0.3:8201    leader      true
vault_4    127.0.0.4:8201    follower    true
```


- - - -

## Start vault_3 in recovery mode.



SSH into **server-a-2**.

```
vagrant ssh server-a-2
```

Start **server-a-2** in recovery mode.

```
export VAULT_TOKEN=$(grep 'Initial Root Token' /vagrant/tmp/vault.init | awk '{print $NF}')
sudo VAULT_ADDR=http://127.0.0.1:8201 vault server -recovery -config=/etc/vault.d/vault.hcl
```

## Create a recovery operational token
Open a new terminal and configure the vault CLI as a client to **server-a-2**.

```
export VAULT_ADDR="http://192.168.50.102:8200"
```

Next, generate a temporary one-time password (OTP).

```
vault operator generate-root -generate-otp -recovery-token | tee ../tmp/recovery_token.txt
```

Sample Output
```
9Z3gV7DDJJ3mZeodWNMwWFmSHo
```

Next, start the generation of the recovery token with the OTP.

```
vault operator generate-root -init \
  -otp=$(cat ../tmp/recovery_token.txt) -recovery-token
```

Sample Output
```
Nonce         13829b90-94eb-b7d8-f774-7b495569562d
Started       true
Progress      0/1
Complete      false
OTP Length    26
```

Next, view the recovery key that was generated during the setup of **vault_3**.

```
$ cat recovery_key-vault_2
aBmg4RDBqihWVwYFG+hJOyNiLFAeFcDEN9yHyaEjc4c=
```

-> NOTE: Recovery key is used instead of unseal key since this cluster has Transit auto-unseal configured.

- [ ] Next, create an encoded token.

```
vault operator generate-root -recovery-token
```

Enter the recovery key when prompted. The output looks similar to below.

```
Operation nonce: d7842f20-0669-18c5-5e58-a92dca58d6d1
Unseal Key (will be hidden): 
Nonce            d7842f20-0669-18c5-5e58-a92dca58d6d1
Started          true
Progress         3/3
Complete         true
Encoded Token    S3RxIh5OcTZzKEBYIh06Vg07G05jcFwjfFg
```


Finally, complete the creation of a recovery token with the `encoded token` and `otp`.

```
vault operator generate-root \
  -decode=<encoded_token> \
  -otp=$(cat ../tmp/recovery_token.txt) \
  -recovery-token
```

Sample Output
```
r.BEHy5r9bs5xxU2ZuV9461p47
```

`-decode` - should be encoded token

- - - -

## Fix the issue in the storage backend
In recovery mode Vault launches with a minimal API enabled. In this mode you are able to interact with the raw system backend.

Use the recovery operational token to list the contents at `sys/raw/sys`.

```
VAULT_TOKEN=r.BEHy5r9bs5xxU2ZuV9461p47 vault list sys/raw/sys
```

Sample Output
```
Keys
----
counters/
policy/
token/
```

Imagine in your investigation you discover that a value or values at a particular path is the cause of the outage. To simulate this assume that the value found at the path `sys/raw/sys/counters` is the root case of the outage.

Delete the counters at `sys/raw/sys/counters`.

```
$ VAULT_TOKEN= r.BEHy5r9bs5xxU2ZuV9461p47 vault delete sys/raw/sys/counters
Success! Data deleted (if it existed) at: sys/raw/sys/counters
```