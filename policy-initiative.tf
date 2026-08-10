resource "azurerm_management_group_policy_set_definition" "landing_zone_baseline" {
  provider            = azurerm.platform
  name                = "landing-zone-baseline"
  policy_type         = "Custom"
  display_name        = "Landing Zone Baseline Governance"
  description         = "Baseline guardrails: tagging, region restriction, public ip control, SKU control, encryption"
  management_group_id = azurerm_management_group.root.id

  parameters = jsonencode({
    allowedLocations = {
      type = "Array"
      metadata = {
        displayName = "Allowed Locations"
        description = "The list of allowed locations for resources."
      }
    }
    requiredTagName = {
      type = "String"
      metadata = {
        displayName = "Required Tag Name"
        description = "The name of the required tag for resources."
      }
    }
    allowedSKUs = {
      type = "Array"
      metadata = {
        displayName = "Allowed VM SKUs"
        description = "The list of allowed SKUs for resources."
      }
    }
    storageEncryptionEffect = {
      type = "String"
      metadata = {
        displayName = "Storage CMK Encryption Effect"
        description = "Effect for storage account customer-managed key encryption policy"
      }
      allowedValues = ["Audit", "Disabled"]
      defaultValue  = "Audit"
    }
  })

  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" # Allowed locations"
    parameter_values = jsonencode({
      "listOfAllowedLocations" = {
        value = "[parameters('allowedLocations')]"
      }
    })
  }

  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99" # Require a tag on resources
    parameter_values = jsonencode({
      "tagName" = {
        value = "[parameters('requiredTagName')]"
      }
    })
  }

  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114" # Deny public IP on NIC
    reference_id         = "no-public-ip-nics"
  }

  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3" # Allowed virtual machine SKUs
    parameter_values = jsonencode({
      "listOfAllowedSKUs" = {
        value = "[parameters('allowedSKUs')]"
      }
    })
  }

  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/6fac406b-40ca-413b-bf8e-0bf964659c25" # Storage accounts should use CMK
    reference_id         = "storage-cmk-encryption-ref"
    parameter_values = jsonencode({
      effect = {
        value = "[parameters('storageEncryptionEffect')]"
      }
    })
  }
}