resource "azurerm_role_definition" "platform_infra_operator" {
  name        = "Platform Infrastructure Operator"
  scope       = azurerm_management_group.platform.id
  description = "Manage networking, DNS, and Key Vault resources in Platform. Cannot modify or delete resources in Platform."

  permissions {
    actions = [
      "Microsoft.Network/*",
      "Microsoft.KeyVault/*/read",
      "Microsoft.KeyVault/vaults/secrets/*",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/deployments/*",

    ]
    not_actions = [
      "Microsoft.Authorization/*/write",
      "Microsoft.Resources/subscriptions/resourceGroups/delete",
    ]
  }
  assignable_scopes = [
    azurerm_management_group.platform.id
  ]
}

resource "azurerm_role_definition" "production_support_operator" {
  name        = "Production Support Operator"
  scope       = azurerm_management_group.production.id
  description = "Read access plus VM restart/scale in production. No delete, no network/security changes"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/restart/action",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Web/sites/restart/action",
    ]
    not_actions = [
      "Microsoft.Authorization/*/write",
      "*/delete",
      "Microsoft.Network/*/write"
    ]
  }
  assignable_scopes = [
    azurerm_management_group.production.id
  ]
}

resource "azurerm_role_definition" "landing_zone_deployer" {
  name        = "Landing Zone Deployer"
  scope       = azurerm_management_group.root.id
  description = "CI/CD deployment identity. full resource deployment rights, explicitly cannot modify RBAC or Policy assignments"

  permissions {
    actions = [
      "*",
    ]
    not_actions = [
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",
      "Microsoft.Authorization/roleDefinitions/write",
      "Microsoft.Authorization/roleDefinitions/delete",
      "Microsoft.Authorization/policyAssignments/write",
      "Microsoft.Authorization/policyAssignments/delete",
      "Microsoft.Authorization/policyDefinitions/write"
    ]
  }
  assignable_scopes = [
    azurerm_management_group.root.id
  ]
}