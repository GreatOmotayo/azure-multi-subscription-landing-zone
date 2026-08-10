resource "azurerm_policy_definition" "environment_tag_scope_match" {
  provider            = azurerm.platform
  name                = "environment-tag-scope-match"
  policy_type         = "Custom"
  mode                = "Indexed"
  display_name        = "Environment Tag must Match deployment scope"
  description         = "Denies resources tagged environment=production if deployed within a non-production management group, preventing tag/scope drift"
  management_group_id = azurerm_management_group.root.id

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "tags['environment']"
          equals = "production"
        },
        {
          value    = "[resourceGroup().id]"
          contains = "non-production"
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "tag_scope_match_nonprod" {
  name                 = "tag-scope-match-nonprod"
  policy_definition_id = azurerm_policy_definition.environment_tag_scope_match.id
  management_group_id  = azurerm_management_group.non_production.id
}