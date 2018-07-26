#!/bin/bash
#set -x

function set_variables () {
export PROJECT_INFO=$(gcloud compute project-info describe --format=json)
export ENVIRONMENT=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal-environment") | .value')
export DNSDOMAIN=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "domain") | .value')
export REGION=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "region") | .value')
export GCPZONE1=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone1") | .value')
export GCPZONE2=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone2") | .value')
export GCPZONE3=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone3") | .value')
export opsman_image_url=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "opsman_image_url") | .value')
export countryName=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "countryName") | .value')
export stateOrProvinceName=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "stateOrProvinceName") | .value')
export stateOrProvinceName=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "stateOrProvinceName") | .value')
export localityName=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "localityName") | .value')
export keyring=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_keyring") | .value')
export GOOGLE_PROJECT=$(gcloud config get-value project)
export BUCKET=$GOOGLE_PROJECT-$ENVIRONMENT
export KEY=$GOOGLE_PROJECT-$ENVIRONMENT
export TERRAFORMVARS=terraform.tfvars
export PIVOTALURL=pcf.$ENVIRONMENT.$DNSDOMAIN
export organizationalUnitName=$DNSDOMAIN
export commonName=$PIVOTALURL
export DNS1=*.apps.$ENVIRONMENT.$DNSDOMAIN
export DNS2=*.system.$ENVIRONMENT.$DNSDOMAIN
export DNS3=*.login.$ENVIRONMENT.$DNSDOMAIN
export DNS4=*.uaa.$ENVIRONMENT.$DNSDOMAIN
export DNS5=*.$ENVIRONMENT.$DNSDOMAIN
export SERVICE_ACCOUNT_KEY=terraform.$ENVIRONMENT.json
}

function create_service_account () {
gcloud iam service-accounts create terraform-$ENVIRONMENT --display-name "Terraform $ENVIRONMENT"
gcloud iam service-accounts keys create "$SERVICE_ACCOUNT_KEY" --iam-account "terraform-$ENVIRONMENT@$GOOGLE_PROJECT.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding $GOOGLE_PROJECT --member 'serviceAccount:terraform-'$ENVIRONMENT'@'$GOOGLE_PROJECT'.iam.gserviceaccount.com' --role 'roles/owner'
}

function generate_self_signed_cert () {
echo "[req]" > $PIVOTALURL.cnf
echo "prompt = no" >> $PIVOTALURL.cnf
echo "distinguished_name = req_distinguished_name" >> $PIVOTALURL.cnf
echo "req_extensions = v3_req" >> $PIVOTALURL.cnf
echo "[req_distinguished_name]" >> $PIVOTALURL.cnf
echo "countryName = $countryName" >> $PIVOTALURL.cnf
echo "stateOrProvinceName = $stateOrProvinceName" >> $PIVOTALURL.cnf
echo "localityName = $localityName" >> $PIVOTALURL.cnf
echo "organizationalUnitName  = $organizationalUnitName" >> $PIVOTALURL.cnf
echo "commonName = $commonName" >> $PIVOTALURL.cnf
echo "[ v3_req ]" >> $PIVOTALURL.cnf
echo "basicConstraints = CA:FALSE" >> $PIVOTALURL.cnf
echo "keyUsage = nonRepudiation, digitalSignature, keyEncipherment" >> $PIVOTALURL.cnf
echo "subjectAltName = @alt_names" >> $PIVOTALURL.cnf
echo "[ alt_names ]" >> $PIVOTALURL.cnf
echo "DNS.1 = $DNS1" >> $PIVOTALURL.cnf
echo "DNS.2 = $DNS2" >> $PIVOTALURL.cnf
echo "DNS.3 = $DNS3" >> $PIVOTALURL.cnf
echo "DNS.4 = $DNS4" >> $PIVOTALURL.cnf
echo "DNS.5 = $DNS5" >> $PIVOTALURL.cnf

openssl genrsa -out $PIVOTALURL.key 2048
openssl req -new -newkey rsa:2048 -key $PIVOTALURL.key -out $PIVOTALURL.csr -config $PIVOTALURL.cnf
openssl x509 -req -days 365 -in $PIVOTALURL.csr -signkey $PIVOTALURL.key -out $PIVOTALURL.crt -extensions v3_req -extfile $PIVOTALURL.cnf
}

function create_terraform_variables () {
echo "env_name         = \"$ENVIRONMENT\"" > $TERRAFORMVARS
echo "region           = \"$REGION\"" >> $TERRAFORMVARS
echo "opsman_image_url = \"$opsman_image_url\"" >> $TERRAFORMVARS
echo "zones            = [\"$GCPZONE1\", \"$GCPZONE2\", \"$GCPZONE3\"]" >> $TERRAFORMVARS
echo "project          = \"$GOOGLE_PROJECT\"" >> $TERRAFORMVARS
echo "dns_suffix       = \"$DNSDOMAIN\"" >> $TERRAFORMVARS
echo "existing_dns_zone       = \"$DNSDOMAIN\"" >> $TERRAFORMVARS

echo "ssl_cert = <<SSL_CERT" >> $TERRAFORMVARS
cat $PIVOTALURL.crt >> $TERRAFORMVARS
echo "SSL_CERT" >> $TERRAFORMVARS

echo "ssl_private_key = <<SSL_KEY" >> $TERRAFORMVARS
cat $PIVOTALURL.key >> $TERRAFORMVARS
echo "SSL_KEY" >> $TERRAFORMVARS

echo "service_account_key = <<SERVICE_ACCOUNT_KEY" >> $TERRAFORMVARS
cat $SERVICE_ACCOUNT_KEY >> $TERRAFORMVARS
echo "SERVICE_ACCOUNT_KEY" >> $TERRAFORMVARS
}

function upload_secret_files () {
gsutil cp $TERRAFORMVARS gs://$BUCKET
gsutil cp $PIVOTALURL.crt gs://$BUCKET
gsutil cp $PIVOTALURL.key gs://$BUCKET
}

function generate_password () {
CLEAR=$(openssl rand -base64 32)
BASE64=$(echo -n "$CLEAR" | base64)
}

function store_password () {
key=${BUCKET}
gcloud kms keyrings create $keyring --location global
gcloud kms keys create $KEY --location global --keyring $keyring --purpose encryption
if [ $? -ne 0 ]; then
     echo "Key already exists skipping to prevent overwriting password"
     	else
     CIPHERTEXT=$(curl -s -X POST "https://cloudkms.googleapis.com/v1/projects/$GOOGLE_PROJECT/locations/global/keyRings/$keyring/cryptoKeys/$KEY:encrypt" -d "{\"plaintext\":\"$BASE64\"}" -H "Authorization:Bearer $(gcloud auth print-access-token)" -H "Content-Type:application/json"| jq -r '.ciphertext') 
     echo ${CIPHERTEXT} > $KEY.txt
     gsutil cp $KEY.txt gs://$BUCKET
if
}

function get_password () {
CIPHERTEXT=$(gsutil cat gs://$BUCKET/$KEY.txt)
BACK2BASE64=$(curl -s -X POST "https://cloudkms.googleapis.com/v1/projects/$GOOGLE_PROJECT/locations/global/keyRings/$keyring/cryptoKeys/$KEY:decrypt" -d "{\"ciphertext\":\"$CIPHERTEXT\"}" -H "Authorization:Bearer $(gcloud auth print-access-token)" -H "Content-Type:application/json"| jq -r '.plaintext') 
DECODE=$(echo "$BACK2BASE64" | base64 --decode && echo)
}


set_variables
create_service_account
generate_self_signed_cert
create_terraform_variables
upload_secret_files
generate_password
store_password
get_password
