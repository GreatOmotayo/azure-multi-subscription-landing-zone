data "azurerm_client_config" "current" {}

# Root of the custom hierarchy - sits directly below Tenant Root Group
resource "azurerm_management_group" "root" {
  display_name = "RealE Root"
  name         = "mg-reale-root"
}

resource "azurerm_management_group" "platform" {
  display_name               = "Platform"
  name                       = "mg-reale-platform"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "landing_zones" {
  display_name               = "Landing Zones"
  name                       = "mg-reale-landingzones"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "production" {
  display_name               = "Production"
  name                       = "mg-reale-production"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

resource "azurerm_management_group" "non_production" {
  display_name               = "Non-Production"
  name                       = "mg-reale-nonproduction"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

resource "azurerm_management_group" "decommissioned" {
  display_name               = "Decommissioned"
  name                       = "mg-reale-decommissioned"
  parent_management_group_id = azurerm_management_group.root.id
}