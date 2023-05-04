locals {
  registration_token      = azurerm_virtual_desktop_host_pool_registration_info.registration_info.token
  shutdown_command        = "shutdown -r -t 10"
  exit_code_hack          = "exit 0"
  commandtorun            = "New-Item -Path HKLM:/SOFTWARE/Microsoft/RDInfraAgent/AADJPrivate"
  aadj_powershell_command = "${local.commandtorun}; ${local.shutdown_command}; ${local.exit_code_hack}"
}

resource "random_string" "AVD_local_password" {
  count            = var.rdsh_count
  length           = 16
  special          = true
  min_special      = 2
  override_special = "*!@#?"
}

resource "azurerm_resource_group" "rg" {
  name     = var.rg
  location = var.resource_group_location
}

resource "azurerm_role_assignment" "rbac" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.principal_id
}

resource "azurerm_virtual_network" "vnet" {
  name                = "avd-vnet"
  location            = "West Europe"
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_range
}

resource "azurerm_virtual_network_dns_servers" "dns" {
  virtual_network_id = azurerm_virtual_network.vnet.id
  dns_servers        = var.dns_servers
}

resource "azurerm_subnet" "default_snet" {
  name                 = "default"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = var.subnet_range
}

resource "azurerm_virtual_desktop_workspace" "workspace" {
  name                = "workspace"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_desktop_application_group" "desktopapp" {
  name                = "desktopapp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.hostpool.id
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "workspacedesktopapp" {
  workspace_id         = azurerm_virtual_desktop_workspace.workspace.id
  application_group_id = azurerm_virtual_desktop_application_group.desktopapp.id
}

resource "azurerm_virtual_desktop_host_pool" "hostpool" {
  name                  = "hostpool"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  type                  = "Pooled"
  validate_environment  = true
  load_balancer_type    = "BreadthFirst"
  custom_rdp_properties = "targetisaadjoined:i:1;use multimon:i:0;"
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "registration_info" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.hostpool.id
  expiration_date = "2023-06-01T23:40:52Z"
}

resource "azurerm_network_interface" "avd_vm_nic" {
  count               = var.rdsh_count
  name                = "${var.prefix}-${count.index + 1}-nic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "nic${count.index + 1}_config"
    subnet_id                     = azurerm_subnet.default_snet.id
    private_ip_address_allocation = "dynamic"
  }

  depends_on = [
    azurerm_resource_group.rg,
    azurerm_subnet.default_snet
  ]
}

resource "azurerm_windows_virtual_machine" "avd_vm" {
  count                 = var.rdsh_count
  name                  = "${var.prefix}-${count.index + 1}"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  network_interface_ids = ["${azurerm_network_interface.avd_vm_nic.*.id[count.index]}"]
  provision_vm_agent    = true
  admin_username        = var.local_admin_username
  admin_password        = var.local_admin_password

  os_disk {
    name                 = "${lower(var.prefix)}-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-10"
    sku       = "20h2-evd"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_resource_group.rg,
    azurerm_network_interface.avd_vm_nic
  ]
}

resource "azurerm_virtual_machine_extension" "AADLoginForWindows" {
  depends_on = [
    azurerm_windows_virtual_machine.avd_vm,
    azurerm_virtual_machine_extension.vmext_aadjprivate
  ]
  count                      = var.rdsh_count
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd_vm.*.id[count.index]
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
        "mdmId" : "0000000a-0000-0000-c000-000000000000"
    }
  SETTINGS
}

resource "azurerm_virtual_machine_extension" "vmext_dsc" {
  count                      = var.rdsh_count
  name                       = "${var.prefix}${count.index + 1}-avd_dsc"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd_vm.*.id[count.index]
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "modulesUrl": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_01-19-2023.zip",
      "configurationFunction": "Configuration.ps1\\AddSessionHost",
      "properties": {
        "hostPoolName":"${azurerm_virtual_desktop_host_pool.hostpool.name}",
        "aadJoin": true,
        "UseAgentDownloadEndpoint": true,
        "aadJoinPreview": false,
        "mdmId": "0000000a-0000-0000-c000-000000000000",
        "sessionHostConfigurationLastUpdateTime": ""
      }
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
  {
    "properties": {
      "registrationInfoToken": "${local.registration_token}"
    }
  }
PROTECTED_SETTINGS

  depends_on = [
    azurerm_virtual_machine_extension.AADLoginForWindows,
    azurerm_virtual_desktop_host_pool.hostpool
  ]
}

resource "azurerm_virtual_machine_extension" "vmext_aadjprivate" {
  count                = var.rdsh_count
  name                 = "AADJPRIVATE"
  virtual_machine_id   = azurerm_windows_virtual_machine.avd_vm.*.id[count.index]
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"
  settings             = <<SETTINGS
    {
        "commandToExecute": "powershell.exe -Command \"${local.aadj_powershell_command}\""
    }
SETTINGS
}
