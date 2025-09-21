#!/bin/sh

# Generate per-profile EKS kubeconfigs under ~/e-aws/<profile>/<cluster>
# Requires: aws, yq, curl

set -e

usage() {
  echo "Usage:" 1>&2
  echo "  $0 <aws_profile> [cluster] [region]" 1>&2
  echo "If only <aws_profile> is provided, discovers clusters across regions and prints runnable commands." 1>&2
}

setup_eks() {
  profile="$1"
  cluster="$2"
  region="$3"

  if [ -z "$profile" ] || [ -z "$cluster" ] || [ -z "$region" ]; then
    usage
    exit 1
  fi

  dest_dir="$HOME/e-aws/$profile"
  mkdir -p "$dest_dir"
  export AWS_PROFILE="$profile"
  export KUBECONFIG="$dest_dir/$cluster"

  echo "Configuring AWS profile $profile, EKS cluster $cluster, region $region in kubeconfig $KUBECONFIG"
  aws eks update-kubeconfig \
    --name "$cluster" \
    --region "$region" \
    --profile "$profile" \
    --kubeconfig "$KUBECONFIG"

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
  echo "EKS cluster setup completed: $KUBECONFIG"
}

list_and_emit() {
  profile="$1"
  if [ -z "$profile" ]; then
    usage
    exit 1
  fi
  tmp="/tmp/$$.setup-aws"
  {
    echo "set -e"
    echo "mkdir -p \"$HOME/e-aws/$profile\""
    # Discover all regions for the account then enumerate clusters per region
    for region in $(aws ec2 describe-regions --profile "$profile" --query 'Regions[].RegionName' --output text); do
      for c in $(aws eks list-clusters --profile "$profile" --region "$region" --output text --query 'clusters[]'); do
        echo "aws eks update-kubeconfig --name \"$c\" --region \"$region\" --profile \"$profile\" --kubeconfig \"$HOME/e-aws/$profile/$c\""
      done
    done
  } > "$tmp"
  echo "$tmp"
}

profile="$1"
cluster="$2"
region="$3"

if [ -z "$profile" ]; then
  usage
  exit 1
fi

if [ -n "$profile" ] && [ -z "$cluster" ]; then
  # emit a runnable script with direct aws commands
  out="$(list_and_emit "$profile")"
  echo "Discovered clusters. To configure, run: bash $out"
  exit 0
fi

if [ -z "$region" ]; then
  # Attempt to discover region by searching all regions; first match wins
  for r in $(aws ec2 describe-regions --profile "$profile" --query 'Regions[].RegionName' --output text); do
    if aws eks describe-cluster --name "$cluster" --region "$r" --profile "$profile" >/dev/null 2>&1; then
      region="$r"
      break
    fi
  done
fi

setup_eks "$profile" "$cluster" "$region"
