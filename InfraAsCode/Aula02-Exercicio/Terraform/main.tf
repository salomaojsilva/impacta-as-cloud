terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "as02-rg" {
    name     = "rg"
    location = "eastus"
}


resource "azurerm_subnet" "as02-subnet" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.as02-rg.name
  virtual_network_name = azurerm_virtual_network.as02-vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_virtual_network" "as02-vnet" {
  name                = "vnet"
  location            = azurerm_resource_group.as02-rg.location
  resource_group_name = azurerm_resource_group.as02-rg.name
  address_space       = ["10.0.0.0/16"]
   
}

resource "azurerm_network_security_group" "as02-nsg" {
  name                = "nsg"
  location            = azurerm_resource_group.as02-rg.location
  resource_group_name = azurerm_resource_group.as02-rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "web"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "mysql"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}


resource "azurerm_public_ip" "as02-ip" {
  name                = "publicip"
  resource_group_name = azurerm_resource_group.as02-rg.name
  location            = azurerm_resource_group.as02-rg.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "as02-ni" {
name                = "nic"
location            = azurerm_resource_group.as02-rg.location
resource_group_name = azurerm_resource_group.as02-rg.name

  ip_configuration {
    name                          = "ipvm"
    subnet_id                     = azurerm_subnet.as02-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.as02-ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "as02-nicnsg" {
  network_interface_id      = azurerm_network_interface.as02-ni.id
  network_security_group_id = azurerm_network_security_group.as02-nsg.id
}

resource "azurerm_linux_virtual_machine" "as02-vm" {
  name                = "as02-virtualmachine"
  resource_group_name = azurerm_resource_group.as02-rg.name
  location            = azurerm_resource_group.as02-rg.location
  size                = "Standard_DS1_v2"
  admin_username      = "adminuser"
  admin_password      = "adminuser@as02"
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.as02-ni.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

resource "null_resource" "install-apache" {
  triggers = {
    order = azurerm_linux_virtual_machine.as02-vm.id
  }

  connection {
    host = element(aws_instance.cluster.*.public_ip, 0)
  }

  provisioner "remote-exec" {
      connection {
        type = "ssh"
        user = "adminuser"
        password = "adminuser@as02"
        host= azurerm_public_ip.as02-ip.ip_address  
      }
      inline = [
        "sudo apt update",
        # "sudo apt install -y apache2",
        "sudo apt install -y mysql-server-5.7",
        "sudo mysql -e \"create user 'teste'@'%' identified by 'pass';\"",
        "sudo mysql -e \"create user 'root'@'%' identified by '';\"",
        "sudo mysql -e \"create database if not exists dbTeste;\"",
        "sudo mysql -e \"use dbTeste; create table if not exists tabela1 (id int) engine=InnoDB;\"",        
      ]
  }
}

