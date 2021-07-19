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

resource "azurerm_resource_group" "mysql-rg" {
    name     = "mysql-rg"
    location = "eastus"
    tags     = {
        "Environment" = "Ex.MySQL"
    }
}

resource "azurerm_virtual_network" "mysql-vnet" {
    name                = "mysql-vnet"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.mysql-rg.name
}

resource "azurerm_subnet" "mysql-subnet" {
    name                 = "mysql-subnet"
    resource_group_name  = azurerm_resource_group.mysql-rg.name
    virtual_network_name = azurerm_virtual_network.mysql-vnet.name
    address_prefixes       = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "mysql-ip" {
    name                         = "mysql-ip"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.mysql-rg.name
    allocation_method            = "Static"
}

resource "azurerm_network_security_group" "mysql-nsg" {
    name                = "mysql-nsg"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.mysql-rg.name

    security_rule {
        name                       = "mysql"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "mysql-ni" {
    name                      = "mysql-ni"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.mysql-rg.name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.mysql-subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.mysql-ip.id
    }
}

resource "azurerm_network_interface_security_group_association" "mysql-nisga" {
    network_interface_id      = azurerm_network_interface.mysql-ni.id
    network_security_group_id = azurerm_network_security_group.mysql-nsg.id
}

data "azurerm_public_ip" "mysql-dbip" {
  name                = azurerm_public_ip.mysql-ip.name
  resource_group_name = azurerm_resource_group.mysql-rg.name
}

resource "azurerm_storage_account" "mysqlstorage2" {
    name                        = "mysqlstorage2"
    resource_group_name         = azurerm_resource_group.mysql-rg.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

resource "azurerm_linux_virtual_machine" "mysql-vm" {
  name                = "as02-virtualmachine"
  resource_group_name = azurerm_resource_group.mysql-rg.name
  location            = azurerm_resource_group.mysql-rg.location
  size                = "Standard_DS1_v2"
  admin_username      = "adminuser"
  admin_password      = "adminuser@as02"
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.mysql-ni.id,
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

output "public_ip_address_mysql" {
  value = azurerm_public_ip.mysql-ip.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.mysql-vm]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "adminuser"
            password = "adminuser@as02"
            host = data.azurerm_public_ip.mysql-dbip.ip_address
        }
        source = "config"
        destination = "/home/adminuser"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "adminuser"
            password = "adminuser@as02"
            host = data.azurerm_public_ip.mysql-dbip.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/adminuser/config/user.sql",
            "sudo cp -f /home/adminuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}