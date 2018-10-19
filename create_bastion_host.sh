#!/bin/bash
#set -x

function set_variables () {
if [ $# -ne 1 ]; then
    echo $0: usage: Requires argument of environment e.g. web, mobile, unicorn, zebra, just pick a name, anyname 
    exit 1
fi
export QUIET=0
export ENVIRONMENT=$1
export GOOGLE_PROJECT=$(gcloud config list --format 'value(core.project)')
export ZONE=us-central1-a
export REGION=us-central1
export BASTION_HOST=$GOOGLE_PROJECT-$ENVIRONMENT
export BUCKET=$GOOGLE_PROJECT-$ENVIRONMENT
export STARTUP=install_prerequisites.sh
export METADATA=pivotal-environment
}

function ask_for_confirmation {
  if [ $QUIET -eq 1 ]; then
    return 0
  fi
  read -p "${1} [y/N] " yn
  case $yn in
    [Yy]* )
      return 0
      ;;
    * )
      exit 1
      ;;
  esac
}

function create_bucket () {
gsutil mb -p $GOOGLE_PROJECT -c regional -l $REGION gs://$BUCKET/
gsutil cp $STARTUP gs://$BUCKET/
}

function create_bastion () {
gcloud beta compute instances create "$BASTION_HOST" --zone "$ZONE" --machine-type "n1-standard-1" --subnet "default" --metadata "startup-script-url=gs://$BUCKET/$STARTUP" --maintenance-policy "MIGRATE" --scopes "https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring.write","https://www.googleapis.com/auth/trace.append","https://www.googleapis.com/auth/devstorage.read_write","https://www.googleapis.com/auth/cloud-platform" --min-cpu-platform "Automatic" --boot-disk-size "50" --boot-disk-type "pd-standard" --boot-disk-device-name "$BASTION_HOST"
gcloud --project $GOOGLE_PROJECT compute project-info add-metadata --metadata=$METADATA=$ENVIRONMENT
}

set_variables $1
ask_for_confirmation 'Do you want to create Storage Bucket and Bastion host named '$BUCKET'?'
create_bucket
create_bastion
