provider "azurerm" {
  features {}
}

# -------------------------------
# RESOURCE GROUP
# -------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-terraform-demo"
  location = "East US"
}

# -------------------------------
# VIRTUAL NETWORK
# -------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-demo"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# -------------------------------
# PUBLIC IP FOR LOAD BALANCER
# -------------------------------
resource "azurerm_public_ip" "lb_ip" {
  name                = "lb-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -------------------------------
# LOAD BALANCER
# -------------------------------
resource "azurerm_lb" "lb" {
  name                = "nginx-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb_ip.id
  }
}

# -------------------------------
# BACKEND POOL
# -------------------------------
resource "azurerm_lb_backend_address_pool" "bpool" {
  name            = "backend-pool"
  loadbalancer_id = azurerm_lb.lb.id
}

# -------------------------------
# HEALTH PROBE (FIXED)
# -------------------------------
resource "azurerm_lb_probe" "probe" {
  name                = "http-probe"
  loadbalancer_id     = azurerm_lb.lb.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
}

# -------------------------------
# LOAD BALANCER RULE
# -------------------------------
resource "azurerm_lb_rule" "http_rule" {
  name                           = "http-rule"
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpool.id]
  probe_id                       = azurerm_lb_probe.probe.id
}

# -------------------------------
# NETWORK INTERFACE
# -------------------------------
resource "azurerm_network_interface" "nic" {
  name                = "nic-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"

    # Attach to Load Balancer
    load_balancer_backend_address_pools_ids = [
      azurerm_lb_backend_address_pool.bpool.id
    ]
  }
}

# -------------------------------
# VIRTUAL MACHINE (NGINX)
# -------------------------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "nginx-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  admin_password                  = "Password1234!"
  disable_password_authentication = false

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

  # 🔥 Install NGINX automatically
  custom_data = base64encode(<<EOF
#!/bin/bash
apt update -y
apt install -y nginx
systemctl enable nginx
systemctl start nginx
EOF
  )
}
