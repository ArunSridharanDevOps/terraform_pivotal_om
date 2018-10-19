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
}

function install_pivotal_infrastructure () {
ID=$(whoami)
sudo chown -R $ID:$ID /$ENVIRONMENT
gsutil cp gs://$BUCKET/$TERRAFORMVARS /$ENVIRONMENT
cd /$ENVIRONMENT
terraform init /$ENVIRONMENT
terraform apply -auto-approve /$ENVIRONMENT
gsutil cp /$ENVIRONMENT/$TERRAFORMSTATE gs://$BUCKET/
}

set_variables
install_pivotal_infrastructure
