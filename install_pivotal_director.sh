#!/bin/bash
set -x

function set_variables () {
export PROJECT_INFO=$(gcloud compute project-info describe --format=json)
export ENVIRONMENT=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal-environment") | .value')
export DNSDOMAIN=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "domain") | .value')
export NTPADDRESS=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "ntpaddress") | .value')
export REGION=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "region") | .value')
export GCPZONE1=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone1") | .value')
export GCPZONE2=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone2") | .value')
export GCPZONE3=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone3") | .value')
export USER=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_user") | .value')
export opsman_image_url=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "opsman_image_url") | .value')
export keyring=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_keyring") | .value')
export GOOGLE_PROJECT=$(gcloud config get-value project)
export BUCKET=$GOOGLE_PROJECT-$ENVIRONMENT
export KMSBUCKET=$GOOGLE_PROJECT-vault
export KEY=$GOOGLE_PROJECT-$ENVIRONMENT
export PIVOTALURL=pcf.$ENVIRONMENT.$DNSDOMAIN
export SERVICE_ACCOUNT_KEY=terraform.$ENVIRONMENT.json
export SERVICE_ACCOUNT_KEY_2_STRING=$(cat $SERVICE_ACCOUNT_KEY |jq 'tostring')
get_password
export OM_CORE_COMMAND="om --target https://$PIVOTALURL --skip-ssl-validation --username $USER --password $PASS"
}

function get_password () {
CIPHERTEXT=$(gsutil cat gs://$KMSBUCKET/$PIVOTALURL.txt)
BACK2BASE64=$(curl -s -X POST "https://cloudkms.googleapis.com/v1/projects/$GOOGLE_PROJECT/locations/global/keyRings/$keyring/cryptoKeys/$KEY:decrypt" -d "{\"ciphertext\":\"$CIPHERTEXT\"}" -H "Authorization:Bearer $(gcloud auth print-access-token)" -H "Content-Type:application/json"| jq -r '.plaintext') 
DECODE=$(echo "$BACK2BASE64" | base64 --decode && echo)
PASS=$DECODE
}

function configure_ops_manager_authetication () {
$OM_CORE_COMMAND configure-authentication --username $USER --password $PASS --decryption-passphrase $PASS
}

function configure_ops_iaas () {
$OM_CORE_COMMAND configure-director --iaas-configuration '{"project":"'$GOOGLE_PROJECT'","default_deployment_tag":"'$ENVIRONMENT'","associated_service_account":"'$ENVIRONMENT'-opsman@'$GOOGLE_PROJECT'.iam.gserviceaccount.com"}'
}

function configure_ops_az () {
$OM_CORE_COMMAND configure-director --az-configuration '
  [
    {"name": "'$GCPZONE1'"},
    {"name": "'$GCPZONE2'"},
    {"name": "'$GCPZONE3'"}
  ]
'
}

function configure_ops_network () {
$OM_CORE_COMMAND configure-director --networks-configuration '{  
"icmp_checks_enabled": false,
  "networks": [
    {
      "name": "'$ENVIRONMENT'-infrastructure-subnet",
      "subnets": [
        {
          "iaas_identifier": "'$ENVIRONMENT'-pcf-network/'$ENVIRONMENT'-infrastructure-subnet/'$REGION'",
          "cidr": "10.0.0.0/26",
          "reserved_ip_ranges": "10.0.0.0-10.0.0.4",
          "dns": "8.8.8.8",
          "gateway": "10.0.0.1",
          "availability_zone_names": [
            "'$GCPZONE1'",
            "'$GCPZONE2'",
            "'$GCPZONE3'"
          ]
        }
      ]
    },
    {
      "name": "'$ENVIRONMENT'-pas-subnet",
      "subnets": [
        {
          "iaas_identifier": "'$ENVIRONMENT'-pcf-network/'$ENVIRONMENT'-pas-subnet/'$REGION'",
          "cidr": "10.0.4.0/24",
          "reserved_ip_ranges": "10.0.4.0-10.0.4.4",
          "dns": "8.8.8.8",
          "gateway": "10.0.4.1",
          "availability_zone_names": [
            "'$GCPZONE1'",
            "'$GCPZONE2'",
            "'$GCPZONE3'"
          ]
        }
      ]
    },
    {
      "name": "'$ENVIRONMENT'-services-subnet",
      "subnets": [
        {
          "iaas_identifier": "'$ENVIRONMENT'-pcf-network/'$ENVIRONMENT'-services-subnet/'$REGION'",
          "cidr": "10.0.8.0/24",
          "reserved_ip_ranges": "10.0.8.0-10.0.8.4",
          "dns": "8.8.8.8",
          "gateway": "10.0.8.1",
          "availability_zone_names": [
            "'$GCPZONE1'",
            "'$GCPZONE2'",
            "'$GCPZONE3'"
          ]
        }
      ]
    }
  ]
}}'
}

function configure_ops_network_assignment () {
$OM_CORE_COMMAND configure-director --network-assignment '{
"singleton_availability_zone": {
 "name": "'$GCPZONE1'"
},
"network": {
 "name": "'$ENVIRONMENT'-infrastructure-subnet"
  }
}'  
}

function configure_ops_ntp () {
$OM_CORE_COMMAND configure-director --director-configuration '{"ntp_servers_string": "'$NTPADDRESS'"}'
}

function configure_ops_uaac_connection () {
uaac target https://$PIVOTALURL/uaa --skip-ssl-validation
uaac token owner get opsman admin -s '' -p $PASS
}

function configure_internet_connected () {
$OM_CORE_COMMAND configure-director --resource-configuration "{\"director\":{\"internet_connected\":false}}"
$OM_CORE_COMMAND configure-director --resource-configuration "{\"compilation\":{\"internet_connected\":false}}"
}

function apply_ops_manager_changes () {
$OM_CORE_COMMAND apply-changes
}

set_variables
configure_ops_manager_authetication
configure_ops_iaas
configure_ops_az
configure_ops_network
configure_ops_network_assignment
configure_ops_ntp
configure_ops_uaac_connection
configure_internet_connected
apply_ops_manager_changes
