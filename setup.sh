#!/bin/sh

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

function setup_project() {
  project=$1
  gcloud container clusters list --format json --project $project | jq -r  '.[]|"setup '$project' \(.name) \(.zone)"' > /tmp/$$
  source /tmp/$$
  exit
}

function setup() {
  project=$1
  cluster=$2
  region=$3
  dest_dir=~/e/$project
  mkdir -p $dest_dir
  export KUBECONFIG=$dest_dir/$cluster
  echo "Configuring project $project, cluster $cluster, region $region in kubeconfig $KUBECONFIG"
  dns_endpoint=$(gcloud beta container clusters get-credentials --project $project $cluster --region $region --dns-endpoint)
  if [ "$?" -ne 0 ] ; then
    echo Unable to use --dns-endpoint for GKFE, switching to direct access
    gcloud container clusters get-credentials --project $project $cluster --region $region
  fi

  # test for reachability
  master=$(cat $KUBECONFIG |  yq -r .clusters[0].cluster.server)
  set +e
  reach=$(curl --silent -k -m 5 $master)
  if [ "$?" = "28" ] ; then
    echo "Kubernetes control plane at $master is unreachable"
    exit 1
  fi
  set -e
  echo "GKE cluster setup completed: $dest_dir/$cluster"
}

set -e
project=$1
cluster=$2
if [ "$project" != "" ] ; then
  if [ "$cluster" != "" ] ; then
    region=$(gcloud container clusters list --project $project| grep $cluster | awk '{print $2}')
    setup $project $cluster $region
    exit
  else
    setup_project $project
  fi
fi
exit

cur_proj=$(gcloud config get project)
echo "GCP Project[$cur_proj]:"
read project
if [ "$project" = "" ] ; then
  project=$cur_proj
fi
echo Fetching clusters in $project
gcloud container clusters list --project $project
echo Cluster:
read cluster
echo Region[us-central1]:
read region
if [ "$region" = "" ] ; then
  region=us-central1
fi
setup $project $cluster $region
