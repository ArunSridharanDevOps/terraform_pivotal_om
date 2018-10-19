#!/bin/bash
set -x

function set_variables () {
export PROJECT_INFO=$(gcloud compute project-info describe --format=json)
export ENVIRONMENT=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal-environment") | .value')
export PIVNETTOKEN=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivnettoken") | .value')
export ERTDOWNLOADURL_LARGE=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "ertdownloadurl_large") | .value')
export ERTDOWNLOADURL_SMALL=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "ertdownloadurl_small") | .value')
export ERTDOWNLOAD_LARGE=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "ertdownload_large") | .value')
export ERTDOWNLOAD_SMALL=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "ertdownload_small") | .value')
export STEMDOWNLOADURL=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "stemdownloadurl") | .value')
export STEMDOWNLOAD=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "stemdownload") | .value')
export FOOTPRINT=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "footprint") | .value')
export PIVOTAL_SMALL_INTERNET=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_small_internet") | .value')
export PIVOTAL_LARGE_INTERNET=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_large_internet") | .value')
export PIVOTAL_SMALL_INTSTANCES=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_small_instances") | .value')
export PIVOTAL_LARGE_INTSTANCES=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_large_instances") | .value')
export ERTVERSION=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "ertversion") | .value')
export DNSDOMAIN=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "domain") | .value')
export NTPADDRESS=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "ntpaddress") | .value')
export REGION=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "region") | .value')
export GCPZONE1=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone1") | .value')
export GCPZONE2=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone2") | .value')
export GCPZONE3=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "gcpzone3") | .value')
export USER=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_user") | .value')
export keyring=$(echo $PROJECT_INFO | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal_keyring") | .value')
export GOOGLE_PROJECT=$(gcloud config get-value project)
export BUCKET=$GOOGLE_PROJECT-$ENVIRONMENT
export KMSBUCKET=$GOOGLE_PROJECT-VAULT
export KEY=$GOOGLE_PROJECT-$ENVIRONMENT
export PIVOTALURL=pcf.$ENVIRONMENT.$DNSDOMAIN
export PRIVATE_KEY=$(/usr/bin/env ruby -e 'p ARGF.read' $PIVOTALURL.key)
export SSL_CERT=$(/usr/bin/env ruby -e 'p ARGF.read' $PIVOTALURL.crt)
export ROUTER_SSL_CERT=$(echo '{"cert_pem":'${SSL_CERT}',"private_key_pem":'${PRIVATE_KEY}'}')
export UAA_SSL_CERT=$(echo '{"cert_pem":'${SSL_CERT}',"private_key_pem":'${PRIVATE_KEY}'}')
get_password
export OM_CORE_COMMAND="om --target https://$PIVOTALURL --skip-ssl-validation --username $USER --password $PASS"
}

function get_password () {
CIPHERTEXT=$(gsutil cat gs://$KMSBUCKET/$KEY.txt)
BACK2BASE64=$(curl -s -X POST "https://cloudkms.googleapis.com/v1/projects/$GOOGLE_PROJECT/locations/global/keyRings/$keyring/cryptoKeys/$KEY:decrypt" -d "{\"ciphertext\":\"$CIPHERTEXT\"}" -H "Authorization:Bearer $(gcloud auth print-access-token)" -H "Content-Type:application/json"| jq -r '.plaintext') 
DECODE=$(echo "$BACK2BASE64" | base64 --decode && echo)
export PASS=$DECODE
}

function download_elastic_runtime_code () {
ACCESS_TOKEN=$(curl POST 'https://network.pivotal.io/api/v2/authentication/access_tokens HTTP/1.1' --header 'Accept: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5' --header 'Content-Type: application/x-www-form-urlencoded' --data '{"refresh_token":"'${PIVNETTOKEN}'"}' | jq -r '.access_token')
curl -i -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $ACCESS_TOKEN" -X GET https://network.pivotal.io/api/v2/authentication
if [ $FOOTPRINT="small" ]; then
wget -O "$ERTDOWNLOAD_SMALL" --header="Authorization: Bearer $ACCESS_TOKEN" -X GET https://$ERTDOWNLOADURL_SMALL
   else 
wget -O "$ERTDOWNLOAD_LARGE" --header="Authorization: Bearer $ACCESS_TOKEN" -X GET https://$ERTDOWNLOADURL_LARGE
fi
wget -O "$STEMDOWNLOAD" --header="Authorization: Bearer $ACCESS_TOKEN" -X GET https://$STEMDOWNLOADURL
}

function upload_elastic_runtime_code () {
if [ $FOOTPRINT="small" ]; then
$OM_CORE_COMMAND upload-product --product $ERTDOWNLOAD_SMALL
  else
$OM_CORE_COMMAND upload-product --product $ERTDOWNLOAD_LARGE
fi
$OM_CORE_COMMAND stage-product --product-name cf --product-version $ERTVERSION 
$OM_CORE_COMMAND upload-stemcell --stemcell $STEMDOWNLOAD 
$OM_CORE_COMMAND available-products
}

function configure_elastic_runtime_zones () {
$OM_CORE_COMMAND configure-product --product-name cf --product-network "{\"singleton_availability_zone\":{\"name\":\"$GCPZONE1\"},\"other_availability_zones\":[{\"name\":\"$GCPZONE1\"},{\"name\":\"$GCPZONE2\"},{\"name\":\"$GCPZONE3\"}],\"network\":{\"name\":\"ert-network\"}}"

$OM_CORE_COMMAND configure-product --product-name cf --product-properties "{\".cloud_controller.system_domain\":{\"value\":\"sys.$ENVIRONMENT.$DNSDOMAIN\"},\".cloud_controller.apps_domain\":{\"value\":\"apps.$ENVIRONMENT.$DNSDOMAIN\"},\".ha_proxy.skip_cert_verify\":{\"value\":true},\".properties.networking_point_of_entry\":{\"value\":\"external_ssl\"},\".properties.security_acknowledgement\":{\"value\":\"X\"},\".mysql_monitor.recipient_email\":"{\"value\":\"root@$DNSDOMAIN\"}"}"
}

function configure_elastic_runtime_routers () {
TEMPCMD=/tmp/config_router.$$
echo "$OM_CORE_COMMAND configure-product --product-name cf --product-properties '{\".properties.networking_poe_ssl_cert\": {\"value\": $ROUTER_SSL_CERT},\".properties.gorouter_ssl_ciphers\": {\"value\": \"ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384\"},\".properties.haproxy_ssl_ciphers\": {\"value\": \"DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384\"},\".properties.haproxy_forward_tls\": {\"value\": \"disable\"}}'" > $TEMPCMD
chmod 700 $TEMPCMD
$TEMPCMD
rm $TEMPCMD
}

function configure_elastic_runtime_uaa () {
TEMPCMD=/tmp/config_uaa.$$
echo "$OM_CORE_COMMAND configure-product --product-name cf --product-properties '{\".uaa.service_provider_key_credentials\": {\"value\": $UAA_SSL_CERT }}'" > $TEMPCMD
chmod 700 $TEMPCMD
$TEMPCMD
rm $TEMPCMD
}

function configure_elastic_runtime_resources () {
if [ $FOOTPRINT="small" ]; then
for x in $(echo $PIVOTAL_SMALL_INTERNET)
do
$OM_CORE_COMMAND configure-product --product-name cf --product-resources "{\"$x\":{\"internet_connected\":false}}"
done

$OM_CORE_COMMAND configure-product --product-name cf --product-resources "{\"tcp_router\":{\"elb_names\":[\"tcp:$ENVIRONMENT-cf-tcp\"]},\"router\":{\"instances\":1,\"elb_names\":[\"http:$ENVIRONMENT-httpslb\",\"tcp:$ENVIRONMENT-cf-ws\"]}}"

for x in $(echo $PIVOTAL_SMALL_INSTANCES)
do
$OM_CORE_COMMAND --password $PASS configure-product --product-name cf --product-resources "{\"$x\":{\"instances\":1}}"
done
else
for x in $(echo $PIVOTAL_LARGE_INTERNET)
do
$OM_CORE_COMMAND configure-product --product-name cf --product-resources "{\"$x\":{\"internet_connected\":false}}"
done
fi
}

function apply_ops_manager_changes () {
$OM_CORE_COMMAND apply-changes
}

set_variables
#download_elastic_runtime_code
#upload_elastic_runtime_code
#configure_elastic_runtime_zones
#configure_elastic_runtime_routers
#configure_elastic_runtime_uaa
#configure_elastic_runtime_resources
apply_ops_manager_changes
