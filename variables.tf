variable "resource_group_location" {
  default     = "westeurope"
  description = "Location of the resource group."
}

variable "rg" {
  type        = string
  default     = "rg-avd-compute"
  description = "Name of the Resource group in which to deploy session host"
}

variable "rdsh_count" {
  description = "Number of AVD machines to deploy"
  default     = 2
}

variable "prefix" {
  type        = string
  default     = "avdtf"
  description = "Prefix of the name of the AVD machine(s)"
}

variable "vm_size" {
  description = "Size of the machine to deploy"
  default     = "Standard_DS2_v2"
}

variable "local_admin_username" {
  type        = string
  default     = "localadm"
  description = "local admin username"
}

variable "local_admin_password" {
  type        = string
  default     = "ChangeMe123!"
  description = "local admin password"
  sensitive   = true
}

variable "dns_servers" {
  type = list
  description = "DNS Servers for the virtual network"
  default = []
}

variable "vnet_range" {
  type = list
  description = "Virtual Network Address Prefix"
}

variable "subnet_range" {
  type = list
  description = "Subnet Address Prefix"
}

variable "principal_id" {
  type        = string
  description = "ObjectId of the user or group to grant Virtual Machine User Login access"
}