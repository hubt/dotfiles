#!/bin/sh

# Generate per-subscription AKS kubeconfigs under ~/e-azure/<subscription>/<cluster>
# Requires: az, yq, curl

set -e

usage() {
  echo "Usage:" 1>&2
  echo "  $0 <subscription_id_or_name> [resource_group] [cluster]" 1>&2
  echo "If only <subscription> is provided, discovers AKS clusters and prints runnable commands." 1>&2
}

setup_aks() {
  subscription="$1"
  resource_group="$2"
  cluster="$3"

  if [ -z "$subscription" ] || [ -z "$resource_group" ] || [ -z "$cluster" ]; then
    usage
    exit 1
  fi

  az account set --subscription "$subscription"

  dest_dir="$HOME/e-azure/$subscription"
  mkdir -p "$dest_dir"
  export AZURE_SUBSCRIPTION_ID="$subscription"
  export KUBECONFIG="$dest_dir/$cluster"

  echo "Configuring Azure subscription $subscription, AKS cluster $cluster (RG: $resource_group) in kubeconfig $KUBECONFIG"
  az aks get-credentials \
    --subscription "$subscription" \
    --resource-group "$resource_group" \
    --name "$cluster" \
    --overwrite-existing \
    --file "$KUBECONFIG"

  # reachability test (best-effort)
  master=$(yq -r .clusters[0].cluster.server "$KUBECONFIG" 2>/dev/null || true)
  if [ -n "$master" ]; then
    set +e
    curl --silent -k -m 5 "$master" >/dev/null
    if [ "$?" = "28" ] ; then
      echo "Kubernetes control plane at $master is unreachable" 1>&2
      exit 1
    fi
    set -e
  fi
  echo "AKS cluster setup completed: $KUBECONFIG"
}

list_and_emit() {
  subscription="$1"
  if [ -z "$subscription" ]; then
    usage
    exit 1
  fi
  az account set --subscription "$subscription"
  tmp="/tmp/$$.setup-azure"
  {
    echo "set -e"
    echo "mkdir -p \"$HOME/e-azure/$subscription\""
    az aks list --subscription "$subscription" \
      --query '[].{name:name, rg:resourceGroup}' -o tsv \
      | while read -r name rg; do
          echo "az account set --subscription \"$subscription\""
          echo "az aks get-credentials --subscription \"$subscription\" --resource-group \"$rg\" --name \"$name\" --overwrite-existing --file \"$HOME/e-azure/$subscription/$name\""
        done
  } > "$tmp"
  echo "$tmp"
}

subscription="$1"
resource_group="$2"
cluster="$3"

if [ -z "$subscription" ]; then
  usage
  exit 1
fi

if [ -n "$subscription" ] && [ -z "$resource_group" ]; then
  # emit a runnable script with direct az commands
  out="$(list_and_emit "$subscription")"
  echo "Discovered clusters. To configure, run: bash $out"
  exit 0
fi

setup_aks "$subscription" "$resource_group" "$cluster"
