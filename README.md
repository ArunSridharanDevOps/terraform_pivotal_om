Simple Bash scripts to automate the deployment of Pivotal on Google Cloud Platform. 

What these scripts will do:
1) create_bastion.sh will deploy a bastion host and bucket used as a control point to deploy Pivotal.
2) generate_pivotal_secrets.sh will create service account for Terraform, generate a self signed SSL cert, update the terraform.tfvars file, generate password for ops manager, and store the password in GCP KMS.
3) install_pivotal_infrastructure.sh will download the terraform.tfvars file from the bastion bucket, deploy the gcp infrastructure using terraform, ops manager, and copy the tfstate file to the bastion bucket.
4) install_pivotal_director.sh will initialize authetication for Ops manager with the password in KMS and deploy the bosh director using OM tool.
5) install_pivotal_elastic_runtime.sh will download the ERT tile/stemcell, upload the ERT tile/stemcell, configure ERT, and deploy using OM tool.

Requirements:
GCP project with adequate quotas to deploy Pivotal Small or Large. 

Permission to create a bastion host, bucket, and service account.

Update required variables in project metadata. There are a lot of variables, but it's intentional to provide flexibilty. 

TO DO's:
Use a CI/CD pipeline to deploy (Concourse, Jenkins, Travis??) or build a simple wrapper.

Provide option to not generate a self signed cert

Move pivnet token to KMS

Reduce permission from owner to least privilege

Create a script to add required metadata
