resource "azurerm_role_assignment" "platform_team" {
  scope              = azurerm_management_group.platform.id
  role_definition_id = azurerm_role_definition.platform_infra_operator.role_definition_resource_id
  principal_id       = azuread_group.platform_team.object_id
}

resource "azurerm_role_assignment" "landing_zone_deployer" {
  scope              = azurerm_management_group.root.id
  role_definition_id = azurerm_role_definition.landing_zone_deployer.role_definition_resource_id
  principal_id       = var.oidc_service_principal_object_id # your existing federated credential app
}

# Dev/Test - built-in Contributor
resource "azurerm_role_assignment" "devtest_contributors" {
  scope                = "/subscriptions/${var.non_production_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_group.devtest_engineers.object_id
}

# Auditor - built-in Reader, root MG scope
resource "azurerm_role_assignment" "auditor" {
  scope                = azurerm_management_group.root.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.auditors.object_id
}


# Production support - custom role
resource "azurerm_role_assignment" "production_support" {
  scope              = azurerm_management_group.production.id
  role_definition_id = azurerm_role_definition.production_support_operator.role_definition_resource_id
  principal_id       = azuread_group.production_support.object_id
}


