resource "time_sleep" "wait_for_policy_propagation" {
  depends_on      = [azurerm_management_group_policy_set_definition.landing_zone_baseline]
  create_duration = "60s"
}

resource "azurerm_management_group_policy_assignment" "baseline_production" {
  name                 = "baseline-production"
  policy_definition_id = azurerm_management_group_policy_set_definition.landing_zone_baseline.id
  management_group_id  = azurerm_management_group.production.id

  depends_on = [time_sleep.wait_for_policy_propagation]

  parameters = jsonencode({
    allowedLocations = {
      value = ["canadacentral", "canadaeast"]
    }
    requiredTagName = {
      value = "CostCenter"
    }
    allowedSKUs = {
      value = [
        "Standard_B2s"
      ]
    }
    storageEncryptionEffect = {
      value = "Audit"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "baseline_platform" {
  name                 = "baseline-platform"
  policy_definition_id = azurerm_management_group_policy_set_definition.landing_zone_baseline.id
  management_group_id  = azurerm_management_group.platform.id

  depends_on = [time_sleep.wait_for_policy_propagation]

  parameters = jsonencode({
    allowedLocations = {
      value = ["canadacentral", "canadaeast"]
    }
    requiredTagName = {
      value = "CostCenter"
    }
    allowedSKUs = {
      value = [
        "Standard_B2s"
      ]
    }
    storageEncryptionEffect = {
      value = "Audit"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "baseline_non_production" {
  name                 = "baseline-non-production"
  policy_definition_id = azurerm_management_group_policy_set_definition.landing_zone_baseline.id
  management_group_id  = azurerm_management_group.non_production.id

  depends_on = [time_sleep.wait_for_policy_propagation]

  parameters = jsonencode({
    allowedLocations = {
      value = ["canadacentral", "canadaeast"]
    }
    requiredTagName = {
      value = "CostCenter"
    }
    allowedSKUs = {
      value = [
        "Standard_B2s"
      ]
    }
    storageEncryptionEffect = {
      value = "Audit"
    }
  })
}