provider "azurerm" {
  features {}
}

# Existing Resource Group
data "azurerm_resource_group" "rg" {
  name = "myRG-hussain"
}

# Existing VNet
data "azurerm_virtual_network" "vnet" {
  name                = "myVnet"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Existing Subnet
data "azurerm_subnet" "subnet" {
  name                 = "mySubnet"
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_resource_group.rg.name
}

# Existing NSG
data "azurerm_network_security_group" "nsg" {
  name                = "myNSG"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Existing VM Public IP
data "azurerm_public_ip" "vm_ip" {
  name                = "vmPublicIP"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# NIC (new)
resource "azurerm_network_interface" "nic" {
  name                = "myNIC"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = data.azurerm_public_ip.vm_ip.id
  }
}

# Attach NSG
resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = data.azurerm_network_security_group.nsg.id
}

# VM (new)
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "nginxVM"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"

  admin_password                  = "Password1234!"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<EOF
#!/bin/bash
apt update
apt install -y nginx
systemctl enable nginx
systemctl start nginx
EOF
  )
}

# Existing LB Public IP
data "azurerm_public_ip" "lb_ip" {
  name                = "lbPublicIP"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Existing Load Balancer
data "azurerm_lb" "lb" {
  name                = "myLB"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Existing Backend Pool
data "azurerm_lb_backend_address_pool" "pool" {
  name            = "backendPool"
  loadbalancer_id = data.azurerm_lb.lb.id
}

# Attach VM to existing backend pool
resource "azurerm_network_interface_backend_address_pool_association" "lb_assoc" {
  network_interface_id    = azurerm_network_interface.nic.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = data.azurerm_lb_backend_address_pool.pool.id
}

# Existing Probe
data "azurerm_lb_probe" "probe" {
  name            = "http-probe"
  loadbalancer_id = data.azurerm_lb.lb.id
}

# Existing LB Rule (optional – only if NOT exists)
# If rule already exists → COMMENT THIS BLOCK
resource "azurerm_lb_rule" "rule" {
  loadbalancer_id                = data.azurerm_lb.lb.id
  name                           = "http-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIP"
  backend_address_pool_ids       = [data.azurerm_lb_backend_address_pool.pool.id]
  probe_id                       = data.azurerm_lb_probe.probe.id
}
