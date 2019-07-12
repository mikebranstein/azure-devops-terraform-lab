#Resource Group
resource "azurerm_resource_group" "app_rg" {
    name = "tf-${var.application_short_name}-${var.environment}-rg"
    location = "${var.location}"
}
resource "azurerm_app_service_plan" "standard_app_plan" {
    name = "tf-standard-plan"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.app_rg.name}"
    sku {
        tier = "Basic"
        size = "B1"
    }
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

resource "azurerm_app_service" "web_app_service" {
    name = "tf-${var.application_short_name}-${random_integer.ri.result}-${var.environment}-app"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.app_rg.name}"
    app_service_plan_id = "${azurerm_app_service_plan.standard_app_plan.id}"
}

resource "azurerm_cosmosdb_account" "db" {
  name                = "tf-cosmos-${random_integer.ri.result}-${var.environment}-db"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.app_rg.name}"
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  enable_automatic_failover = true

  consistency_policy {
    consistency_level       = "Session"
  }

  geo_location {
    location          = "${var.location}"
    failover_priority = 0
  }
}