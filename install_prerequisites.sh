#!/bin/bash
#set -x

function install_om () {
sudo wget -q -O - https://raw.githubusercontent.com/starkandwayne/homebrew-cf/master/public.key | sudo apt-key add -
sudo echo "deb http://apt.starkandwayne.com stable main" | sudo tee /etc/apt/sources.list.d/starkandwayne.list
sudo apt-get update
sudo apt-get install om
}


function install_om_legacy () {
sudo rm om-linux*
sudo wget https://github.com/pivotal-cf/om/releases/download/0.44.0/om-linux
sudo chmod +x om-linux
sudo cp -p om-linux /usr/bin/om
}

function install_cf_uacc () {
sudo wget -q -O - https://packages.cloudfoundry.org/debian/cli.cloudfoundry.org.key | sudo apt-key add -
sudo echo "deb http://packages.cloudfoundry.org/debian stable main" | sudo tee /etc/apt/sources.list.d/cloudfoundry-cli.list
sudo apt --assume-yes install build-essential
sudo apt-get --assume-yes install ruby-full
sudo apt-get --assume-yes install gem 
sudo gem install cf-uaac 
sudo apt-get install cf-cli
}

function install_terraform () {
sudo apt-get install --assume-yes jq unzip git
latest_version=$(curl --silent https://releases.hashicorp.com/terraform/ |grep terraform |grep -v alpha |grep -v beta | head -1 |awk -F_ '{print $2}' |awk -F[\<\] '{print $1}')
terraform_url=$(curl --silent https://releases.hashicorp.com/index.json | jq '{terraform}' | grep "$latest_version" | grep "url" | egrep "linux.*64" | sort -h | head -1 | awk -F[\"] '{print $4}')
# Download Terraform. URI: https://www.terraform.io/downloads.html
curl -o terraform.zip $terraform_url
# Unzip and install
unzip -o terraform.zip

#Copy to /usr/local/bin
sudo cp -rf terraform /usr/local/bin

#validate download and version
terraform -version
if [ $? -ne 0 ]
then
       echo "Terraform validation failed. Enable set -x to debug"
else 
 	rm -f terraform terraform.zip	
fi
}

function download_terraform_repo () {
ENVIRONMENT=$(gcloud compute project-info describe --format=json | jq -r '.commonInstanceMetadata.items[] | select(.key == "pivotal-environment") | .value')
sudo git clone https://github.com/pivotal-cf/terraforming-gcp /$ENVIRONMENT
sudo git clone https://github.com/jasonbisson/terraform_pivotal_om
}

install_om_legacy
install_cf_uacc
install_terraform
download_terraform_repo
