# Customized the sample values below for your environment and either rename to terraform.tfvars or env.auto.tfvars

prefix               = "avdtflab"
local_admin_username = "localadm"
local_admin_password = "ChangeMe123$"
vnet_range           = ["10.1.0.0/16"]
subnet_range         = ["10.1.0.0/24"]
dns_servers          = ["10.0.1.4", "168.63.129.16"]
principal_id         = "<<add your user or group objectid>>"