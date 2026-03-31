#!/bin/sh

# Generate per-profile EKS kubeconfigs under ~/e-aws/<profile>/<cluster>
# Requires: aws, yq, curl

set -e

DEFAULT_REGIONS="us-east-1 us-east-2 us-west-1 us-west-2 ca-central-1 ca-west-1
  eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-central-2 eu-north-1 eu-south-1 eu-south-2
  ap-northeast-1 ap-northeast-2 ap-northeast-3 ap-southeast-1 ap-southeast-2 ap-southeast-3 ap-southeast-4
  ap-south-1 ap-south-2 ap-east-1 me-south-1 me-central-1 af-south-1 sa-east-1 il-central-1"

usage() {
  echo "Usage: $0 <aws_profile> [cluster] [region]" >&2
  echo "  With only <aws_profile>, discovers clusters and prints runnable commands." >&2
}

all_regions() {
  profile="$1"
  regions="$(aws ec2 describe-regions --all-regions --region us-east-1 --profile "$profile" \
    --query 'Regions[].RegionName' --output text 2>/dev/null || true)"
  echo "${regions:-$DEFAULT_REGIONS}"
}

setup_eks() {
  profile="$1" cluster="$2" region="$3"
  dest="$HOME/e-aws/$profile"
  mkdir -p "$dest"
  export AWS_PROFILE="$profile"
  export KUBECONFIG="$dest/$cluster"

  echo "Configuring EKS: profile=$profile cluster=$cluster region=$region" >&2
  aws eks update-kubeconfig --name "$cluster" --region "$region" \
    --profile "$profile" --kubeconfig "$KUBECONFIG"

  master="$(yq -r .clusters[0].cluster.server "$KUBECONFIG" 2>/dev/null || true)"
  if [ -n "$master" ]; then
    set +e
    curl --silent -k -m 5 "$master" >/dev/null
    curl_exit="$?"
    set -e
    if [ "$curl_exit" = "28" ]; then
      echo "ERROR: control plane at $master is unreachable (timeout)" >&2
      exit 1
    fi
  fi
  echo "Done: $KUBECONFIG" >&2
}

list_and_emit() {
  profile="$1"
  tmp="/tmp/$$.setup-aws"
  {
    echo "set -e"
    echo "mkdir -p \"$HOME/e-aws/$profile\""
    for region in $(all_regions "$profile"); do
      clusters="$(aws eks list-clusters --profile "$profile" --region "$region" \
        --output text --query 'clusters[]' 2>/dev/null || true)"
      [ -z "$clusters" ] && continue
      for c in $clusters; do
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
  usage; exit 1
fi

if [ -z "$cluster" ]; then
  echo "Discovering clusters for profile: $profile" >&2
  out="$(list_and_emit "$profile")"
  echo "To configure, run: bash $out" >&2
  exit 0
fi

if [ -z "$region" ]; then
  echo "Searching all regions for cluster: $cluster" >&2
  for r in $(all_regions "$profile"); do
    if aws eks describe-cluster --name "$cluster" --region "$r" --profile "$profile" >/dev/null 2>&1; then
      region="$r"
      echo "Found $cluster in $region" >&2
      break
    fi
  done
  if [ -z "$region" ]; then
    echo "ERROR: cluster $cluster not found in any region for profile $profile" >&2
    exit 1
  fi
fi

setup_eks "$profile" "$cluster" "$region"
