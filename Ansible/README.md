# PulseGuard — Ansible (kubeadm bootstrap)

Takes the 4 bare Ubuntu 22.04 EC2 instances Terraform created (1 master + 3
workers) and turns them into an actual Kubernetes cluster — containerd,
kubeadm/kubelet/kubectl, `kubeadm init`, Calico CNI, and `kubeadm join` on
every worker.

## Directory layout

```
ansible.cfg              # inventory location, SSH user, connection settings
requirements.yml          # Ansible Galaxy collections this playbook needs
group_vars/all.yml         # cluster-wide vars: k8s version, pod CIDR, CNI manifest
scripts/
  generate-inventory.sh      # builds inventory.ini straight from `terraform output`
tasks/
  common.yml                  # runs on every node: containerd, kubeadm/kubelet/kubectl
  handlers.yml                  # containerd restart handler
  master.yml                     # kubeadm init, Calico, join-token generation
  workers.yml                     # kubeadm join
site.yml                  # the playbook — ties the above together in order
```

`inventory.ini` and `fetched/admin.conf` are **generated at runtime**, not
committed — see `.gitignore`. The admin kubeconfig is full cluster-admin
access; it must never end up in git.

## Prerequisites

```bash
pip install ansible
ansible-galaxy collection install -r requirements.yml
```

You'll also need `jq` installed locally (`generate-inventory.sh` uses it to
parse `terraform output -json`).

## Run order

### 1. Generate the inventory from Terraform's outputs

```bash
cd Ansible
chmod +x scripts/generate-inventory.sh
./scripts/generate-inventory.sh /path/to/pulseguard-key.pem
cat inventory.ini   # sanity check: 1 master + 3 worker IPs, all public
```

### 2. Confirm connectivity before running anything real

```bash
ansible all -m ping
```
Every host should return `"ping": "pong"`. If a host times out, your `my_ip`
in Terraform's security group may be stale — see the Terraform README's
"Updating my_ip" section.

### 3. Run the playbook

```bash
ansible-playbook site.yml
```

This runs, in strict order:
1. **`common.yml` on all 4 nodes** — swap off, kernel modules, sysctl,
   containerd, kubeadm/kubelet/kubectl installed and version-pinned
2. **`master.yml` on the master only** — `kubeadm init`, kubeconfig set up,
   Calico installed, join token generated
3. **`workers.yml` on all 3 workers** — each joins using the token from
   step 2 (this only works because steps run in one playbook execution —
   the master's generated `join_command` fact is visible to the worker
   play via `hostvars['master']['join_command']`)
4. **A verification play** — prints `kubectl get nodes -o wide` from the
   master so you see the result immediately, no manual SSH needed

Every task in `common.yml`, `master.yml`, and `workers.yml` has an
idempotency guard (checks `/etc/kubernetes/admin.conf` or
`/etc/kubernetes/kubelet.conf` before acting), so re-running
`ansible-playbook site.yml` after a partial failure is safe — it won't
re-`kubeadm init` a cluster that already exists.

### 4. Use the cluster from your laptop

```bash
mkdir -p ~/.kube
cp fetched/admin.conf ~/.kube/config
kubectl get nodes
```

## Design notes

**Why `kubeadm init` uses the node's private IP, not its public IP:**
`--apiserver-advertise-address` and `--control-plane-endpoint` are set to
`ansible_default_ipv4.address` (the private IP). Workers join over the
private IP too — all 4 nodes are in the same VPC, and the security group's
self-referencing rule already allows all traffic between them. Using the
public IP here would route control-plane traffic out to the internet and
back in for no reason, and would break if a node's public IP ever changed.

**Why containerd isn't pinned to an exact patch version:** hit the same
"exact version not found" problem class here that came up with the RDS
Postgres engine version in Terraform — apt-repo package availability shifts
over time and by architecture. `kubelet`/`kubeadm`/`kubectl` *are* pinned
(`{{ kubernetes_apt_version }}` in `group_vars/all.yml`) because keeping all
three in lockstep at the same version matters for cluster correctness;
containerd's exact patch version doesn't carry the same risk, so it installs
whatever's current.

## Troubleshooting

- **`couldn't resolve module/action 'community.general.modprobe'`**: forgot
  `ansible-galaxy collection install -r requirements.yml`.
- **`kubelet=1.30.5-1.1: Unable to locate package`**: that exact patch build
  aged out of the apt repo (Kubernetes only keeps a handful of recent patch
  versions per minor line). Check what's actually available on a target
  node: `ssh -i pulseguard-key.pem ubuntu@<ip> apt-cache madison kubelet`,
  then update `kubernetes_apt_version` in `group_vars/all.yml` to match.
- **`ansible all -m ping` times out**: almost always the security group —
  either your IP changed (`terraform apply -var="my_ip=..."` in `Terraform/`)
  or the key path in `inventory.ini` is wrong.
- **`kubeadm join` fails on a worker with a token-expired error**: join
  tokens expire after 24h by default. Re-run `ansible-playbook site.yml` —
  `master.yml` regenerates a fresh token every run (token creation isn't
  idempotency-guarded, only `kubeadm init` itself is).

## Re-running against an already-live cluster

Safe to do — every destructive step is guarded. Useful when you've added a
new worker in Terraform and just need it joined:
```bash
./scripts/generate-inventory.sh /path/to/pulseguard-key.pem   # picks up the new IP
ansible-playbook site.yml --limit workers
```
