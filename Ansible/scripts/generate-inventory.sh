#!/usr/bin/env bash
# Run this after `terraform apply` succeeds in ../Terraform.
# Usage: ./scripts/generate-inventory.sh /path/to/pulseguard-key.pem
set -euo pipefail

KEY_PATH="${1:?Usage: generate-inventory.sh /Users/mac/Desktop/pulse-guard-app/pulseguard-key.pem}"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../Terraform" && pwd)"
OUT_FILE="$(dirname "${BASH_SOURCE[0]}")/../inventory.ini"

MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw master_public_ip)
WORKER_IPS=$(terraform -chdir="$TF_DIR" output -json worker_public_ips | jq -r '.[]')

{
  echo "[master]"
  echo "master ansible_host=$MASTER_IP"
  echo ""
  echo "[workers]"
  i=1
  for ip in $WORKER_IPS; do
    echo "worker-$i ansible_host=$ip"
    i=$((i + 1))
  done
  echo ""
  echo "[k8s_cluster:children]"
  echo "master"
  echo "workers"
  echo ""
  echo "[k8s_cluster:vars]"
  echo "ansible_user=ubuntu"
  echo "ansible_ssh_private_key_file=$KEY_PATH"
  echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
} > "$OUT_FILE"

echo "Wrote $OUT_FILE"
