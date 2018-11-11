#!/bin/bash
#set -x

function set_variables () {
export PROJECT_INFO=$(gcloud compute project-info describe --format=json)
export ENVIRONMENT=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal-environment") | .value')
export DNSDOMAIN=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "domain") | .value')
export opsman_image_url=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "opsman_image_url") | .value')
export internetless=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "internetless") | .value')
export GOOGLE_PROJECT=$(gcloud config get-value project)
export BUCKET=$GOOGLE_PROJECT-$ENVIRONMENT
export TERRAFORMVARS=terraform.tfvars
export TERRAFORMSTATE=terraform.tfstate
export PIVOTALURL=pcf.$ENVIRONMENT.$DNSDOMAIN
export TERRAFORMING_PAS=terraforming-pas
}

function install_pivotal_infrastructure () {
ID=$(whoami)
sudo chown -R $ID:$ID /$ENVIRONMENT/$TERRAFORMING_PAS
gsutil cp gs://$BUCKET/$TERRAFORMVARS /$ENVIRONMENT/$TERRAFORMING_PAS
cd /$ENVIRONMENT/$TERRAFORMING_PAS
terraform init /$ENVIRONMENT/$TERRAFORMING_PAS
terraform apply -auto-approve /$ENVIRONMENT/$TERRAFORMING_PAS
gsutil cp /$ENVIRONMENT/$TERRAFORMING_PAS/$TERRAFORMSTATE gs://$BUCKET/
}

set_variables
install_pivotal_infrastructure
