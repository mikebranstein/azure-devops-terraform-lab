terraform {
  backend "azurerm" {
      key   = "terraform.tfstate"
  }
}

provider "azurerm" {
    tenant_id       = "${var.tenant_id}"
    subscription_id = "${var.subscription_id}"
}

module "todo_app" {
    source = "../_modules/cosmos_web_app/"

    application_short_name = "${var.application_short_name}"
    environment = "${var.environment}"
    location = "${var.location}"
}