resource "azurerm_public_ip" "vmss" {
  name                         = "vmss-public-ip"
  location                     = data.terraform_remote_state.vnet.outputs.resource_group_location
  resource_group_name          = data.terraform_remote_state.vnet.outputs.resource_group_name
  public_ip_address_allocation = "static"
  domain_name_label            = data.terraform_remote_state.vnet.outputs.resource_group_name
  tags                         = var.tags
}

resource "azurerm_lb" "vmss" {
  name                = "vmss-lb"
  location            = data.terraform_remote_state.vnet.outputs.resource_group_location
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vmss.id
  }

  tags = "${var.tags}"
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name
  loadbalancer_id     = azurerm_lb.vmss.id
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name
  loadbalancer_id     = azurerm_lb.vmss.id
  name                = "ingress-probe"
  port                = var.application_port
}

resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name            = data.terraform_remote_state.vnet.outputs.resource_group_name
  loadbalancer_id                = azurerm_lb.vmss.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = var.application_port
  backend_port                   = var.application_port
  backend_address_pool_id        = azurerm_lb_backend_address_pool.bpepool.id
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.vmss.id
}