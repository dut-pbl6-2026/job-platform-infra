terraform {
  required_version = ">= 1.5.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Default: local backend (one state per workspace = one per student subscription).
  # Remote state: see backend.azurerm.hcl.example and `terraform init -backend-config=...`.
  # An empty azurerm block is required for -backend-config to take effect, so it stays commented
  # until you opt in (uncomment the block below, then re-run `terraform init -reconfigure`).
  # backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
