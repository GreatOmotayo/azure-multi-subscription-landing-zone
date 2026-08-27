variable "alert_email_address" {
  type        = string
  description = "Email address to send alert emails to"
}

variable "location" {
  type        = string
  description = "The location of the resources."
  default     = "centralus"
}

variable "platform_subscription_id" {
  type        = string
  description = "The subscription ID of the platform subscription."
}

variable "production_subscription_id" {
  type        = string
  description = "The subscription ID of the production subscription."
}

variable "non_production_subscription_id" {
  type        = string
  description = "The subscription ID of the non-production/dev-test subscription."
}

variable "oidc_service_principal_object_id" {
  type        = string
  description = "Object ID of the Enterprise Application (service principal) used for GitHub Actions OIDC federated CI/CD deployments at the management group root"
}

variable "shared_resource_group_name" {
  type        = string
  description = "The resource group name"
}

variable "tenant_domain" {
  type        = string
  description = "Your tenant's onmicrosoft.com domain, e.g. yourtenant.onmicrosoft.com"
}

variable "budget_amount" {
  type        = number
  description = "Your monthly budget"
}

variable "client_id" {
  type = string
}

variable "tenant_id" {
  type = string
}