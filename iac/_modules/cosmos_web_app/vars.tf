variable "application_short_name" {
    description = "Abbreviated name for the application, used to name associated infrastructure resources"
}

variable "environment" {
    description = "The application environment (Dev, Test, QA, Prod)"
}

variable "location" {
    description = "The Azure Region where resources will be deployed"
}