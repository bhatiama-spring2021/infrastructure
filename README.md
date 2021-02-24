# Infrastructure
This app is used for building, changing, and versioning infrastructure on AWS

## Tools used
* [Hashicorp Terraform](https://www.terraform.io/)

## Prerequisites
Install [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) and [configure CLI profile](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)

## Installation
### Ubuntu/Debian
Add the HashiCorp GPG key.

    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -

Add the official HashiCorp Linux repository.

    sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

Update and install.

    sudo apt-get update && sudo apt-get install terraform

### Other Operating System
To learn how to install Packer for other OS, click [here](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Terraform commands
To initialize terraform:

    terraform init

Validate terraform configuration file:

    terraform plan

Execute and create resources:

    terraform apply

Destroy the resources in AWS:

    terraform destroy

Use in-line variables:

    terraform apply -var="foo=bar"

Passing .tfvars file:

    terraform apply -var-file="dev.tfvars"

## Creating multiple VPCs from same .tf file

### Workspace

    terraform workspace
    new, list, show, select and delete Terraform workspaces.

> Note: Terraform uses default workspace when we initialize project with terraform init

Create new workspace using:

    terraform workspace new bar

Switch to different workspace:

    terraform workspace select foo

To learn more about terraform workspace, click [here](https://www.terraform.io/docs/state/workspaces.html)

## tfvars file specific to this repo
To run the main.tf file, create a .tfvars file with the following variables:

    region = "aws_region"
    cidr_block = "10.0.0.0/16"
    vpc_name = "name_for_vpc"
    zone_count = 3 # Number of subnets to create in VPC
    second_octet = 0 # second octect for your subnet CIDR block
    subnet_name = "name_for_subnet"
    gateway_name = "name_for_internet_gateway"
    route_table_name = "name_for_route_table"
    route_table_cidr_block = "0.0.0.0/0"
