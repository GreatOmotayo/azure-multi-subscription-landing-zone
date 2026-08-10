resource "azurerm_management_group_subscription_association" "platform_subscription" {
  management_group_id = azurerm_management_group.platform.id
  subscription_id     = "/subscriptions/${var.platform_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "production_subscription" {
  management_group_id = azurerm_management_group.production.id
  subscription_id     = "/subscriptions/${var.production_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "non_production_subscription" {
  management_group_id = azurerm_management_group.non_production.id
  subscription_id     = "/subscriptions/${var.non_production_subscription_id}"
}
