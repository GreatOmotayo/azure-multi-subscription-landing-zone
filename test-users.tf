data "azuread_user" "test_platform" {
  user_principal_name = "platform-operator@${var.tenant_domain}"
}

data "azuread_user" "test_prodsupport" {
  user_principal_name = "production-support@${var.tenant_domain}"
}

data "azuread_user" "test_devtest" {
  user_principal_name = "dev-test@${var.tenant_domain}"
}

data "azuread_user" "test_auditor" {
  user_principal_name = "auditor@${var.tenant_domain}"
}

resource "azuread_group_member" "test_platform_membership" {
  group_object_id  = azuread_group.platform_team.object_id
  member_object_id = data.azuread_user.test_platform.object_id
}

resource "azuread_group_member" "test_prodsupport_membership" {
  group_object_id  = azuread_group.production_support.object_id
  member_object_id = data.azuread_user.test_prodsupport.object_id
}

resource "azuread_group_member" "test_devtest_membership" {
  group_object_id  = azuread_group.devtest_engineers.object_id
  member_object_id = data.azuread_user.test_devtest.object_id
}

resource "azuread_group_member" "test_auditor_membership" {
  group_object_id  = azuread_group.auditors.object_id
  member_object_id = data.azuread_user.test_auditor.object_id
}