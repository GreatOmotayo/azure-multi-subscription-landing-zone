terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.34"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"

    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

}

provider "azurerm" {
  features {}
  subscription_id                 = var.platform_subscription_id
  use_oidc                        = true
  client_id                       = var.client_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "core"
}

provider "azurerm" {
  features {}
  alias           = "platform"
  use_oidc        = true
  client_id       = var.client_id
  tenant_id       = var.tenant_id
  subscription_id = var.platform_subscription_id
}

provider "azurerm" {
  features {}
  alias           = "production"
  use_oidc        = true
  client_id       = var.client_id
  tenant_id       = var.tenant_id
  subscription_id = var.production_subscription_id
}

provider "azurerm" {
  features {}
  alias           = "non_production"
  use_oidc        = true
  client_id       = var.client_id
  tenant_id       = var.tenant_id
  subscription_id = var.non_production_subscription_id
}

provider "azuread" {}
