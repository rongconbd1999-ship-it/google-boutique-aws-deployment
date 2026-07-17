#!/bin/bash
#====================================
sudo dnf install -y dnf-plugins-core
#====================================
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
#====================================
sudo dnf install -y terraform
#====================================
mkdir -p /tmp/.terraform-plugins
#====================================
ln -snf /tmp/.terraform-plugins .terraform
#====================================
terraform init -upgrade
#====================================
