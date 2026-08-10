output "management_group_ids" {
  description = "The IDs of the management groups created in this module"
  value = {
    root           = azurerm_management_group.root.id
    platform       = azurerm_management_group.platform.id
    landing_zones  = azurerm_management_group.landing_zones.id
    production     = azurerm_management_group.production.id
    non_production = azurerm_management_group.non_production.id
    decommissioned = azurerm_management_group.decommissioned.id
  }
}

output "policy_initiative_id" {
  description = "ID of the Landing Zone Baseline policy initiative"
  value       = azurerm_management_group_policy_set_definition.landing_zone_baseline.id
}

output "custom_policy_tag_scope_match_id" {
  description = "ID of the custom tag/scope drift policy"
  value       = azurerm_policy_definition.environment_tag_scope_match.id
}

output "custom_role_definition_ids" {
  description = "IDs of the custom role definitions created in this module"
  value = {
    platform_infra_operator     = azurerm_role_definition.platform_infra_operator.role_definition_id
    landing_zone_deployer       = azurerm_role_definition.landing_zone_deployer.role_definition_id
    production_support_operator = azurerm_role_definition.production_support_operator.role_definition_id
  }
}

output "entra_group_ids" {
  description = "Object IDs of the Entra ID security groups created for RBAC assignments in this module"
  value = {
    platform_team      = azuread_group.platform_team.object_id
    devtest_engineers  = azuread_group.devtest_engineers.object_id
    production_support = azuread_group.production_support.object_id
    auditors           = azuread_group.auditors.object_id
  }
}

output "budget_action_group_id" {
  description = "ID of the budget action group created in this module"
  value       = azurerm_monitor_action_group.budget_alerts.id
}
