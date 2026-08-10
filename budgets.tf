resource "azurerm_resource_group" "shared" {
  name     = var.shared_resource_group_name
  location = var.location
}

resource "azurerm_monitor_action_group" "budget_alerts" {
  name                = "landing-zone-budget-alerts"
  resource_group_name = azurerm_resource_group.shared.name
  short_name          = "budget-alert"

  email_receiver {
    name          = "primary-contact"
    email_address = var.alert_email_address
  }
}

resource "azurerm_consumption_budget_subscription" "production" {
  provider        = azurerm.production
  name            = "production-monthly-budget"
  subscription_id = "/subscriptions/${var.production_subscription_id}"

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = "2026-08-01T00:00:00Z"
    end_date   = "2027-08-01T23:59:59Z"
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 80
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 100
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }
}

resource "azurerm_consumption_budget_subscription" "non_production" {
  provider        = azurerm.non_production
  name            = "non-production-monthly-budget"
  subscription_id = "/subscriptions/${var.non_production_subscription_id}"

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = "2026-08-01T00:00:00Z"
    end_date   = "2027-08-01T23:59:59Z"
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 80
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }
}

resource "azurerm_consumption_budget_subscription" "platform" {
  provider        = azurerm.platform
  name            = "platform-monthly-budget"
  subscription_id = "/subscriptions/${var.platform_subscription_id}"

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = "2026-08-01T00:00:00Z"
    end_date   = "2027-08-01T23:59:59Z"
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 80
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }
}

