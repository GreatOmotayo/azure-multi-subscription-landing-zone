resource "azuread_group" "platform_team" {
  display_name     = "Platform-Engineers"
  description      = "Platform infrastructure team - networking, DNS, key Vault"
  security_enabled = true
}

resource "azuread_group" "devtest_engineers" {
  display_name     = "DevTest-Engineers"
  description      = "Dev/Test engineers - full contributor access to non-production subscription"
  security_enabled = true
}

resource "azuread_group" "production_support" {
  display_name     = "Production-Support"
  description      = "Production support team - restart/scale, no delete or network changes"
  security_enabled = true
}

resource "azuread_group" "auditors" {
  display_name     = "Cloud-Auditors"
  description      = "Read-only visibility across the entire landing zone"
  security_enabled = true
}
