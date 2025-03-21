terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
  }
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "besutfstate"
    container_name       = "tfstate"
    key                 = "besu.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
      recover_soft_deleted_keys    = true
    }
  }
}

# Create resource groups for each region
resource "azurerm_resource_group" "besu" {
  for_each = toset(local.regions)
  
  name     = "${var.resource_group_prefix}-${each.key}"
  location = each.key
  tags     = var.tags
}

# Create Azure Key Vault for secrets management
resource "azurerm_key_vault" "besu" {
  for_each = toset(local.regions)
  
  name                = "${lower(replace(var.resource_group_prefix, "-", ""))}${each.key}"
  resource_group_name = azurerm_resource_group.besu[each.key].name
  location           = azurerm_resource_group.besu[each.key].location
  tenant_id          = data.azurerm_client_config.current.tenant_id
  sku_name           = "premium"

  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
  soft_delete_retention_days  = 90

  network_acls {
    bypass                    = "AzureServices"
    default_action           = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.aks[each.key].id]
  }

  tags = var.tags
}

# Create virtual networks for each region
resource "azurerm_virtual_network" "besu" {
  for_each = toset(local.regions)
  
  name                = "${var.resource_group_prefix}-vnet-${each.key}"
  resource_group_name = azurerm_resource_group.besu[each.key].name
  location           = azurerm_resource_group.besu[each.key].location
  address_space      = [var.network.vnet_cidr]
  
  tags = var.tags
}

# Create subnets for AKS clusters
resource "azurerm_subnet" "aks" {
  for_each = toset(local.regions)
  
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.besu[each.key].name
  virtual_network_name = azurerm_virtual_network.besu[each.key].name
  address_prefixes     = [var.network.subnet_cidrs.aks]

  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.ContainerRegistry"
  ]
}

# Create AKS clusters
resource "azurerm_kubernetes_cluster" "besu" {
  for_each = toset(local.regions)
  
  name                = "${var.cluster_prefix}-${each.key}"
  location           = azurerm_resource_group.besu[each.key].location
  resource_group_name = azurerm_resource_group.besu[each.key].name
  dns_prefix         = "${var.cluster_prefix}-${each.key}"
  kubernetes_version = "1.25.6"

  default_node_pool {
    name                = "system"
    vm_size            = "Standard_D4s_v3"
    enable_auto_scaling = true
    min_count          = 1
    max_count          = 3
    vnet_subnet_id     = azurerm_subnet.aks[each.key].id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    load_balancer_sku  = "standard"
    service_cidr       = "10.100.0.0/16"
    dns_service_ip     = "10.100.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  auto_scaler_profile {
    scale_down_delay_after_add = "10m"
    scale_down_unneeded       = "10m"
    max_graceful_termination_sec = "600"
  }

  role_based_access_control_enabled = true
  azure_policy_enabled             = true
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  microsoft_defender {
    enabled = true
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.besu[each.key].id
  }

  tags = var.tags
}

# Create node pools for Besu nodes
resource "azurerm_kubernetes_cluster_node_pool" "besu" {
  for_each = {
    for pair in local.node_pool_configs : "${pair.region}-${pair.pool_name}" => pair
  }

  name                  = each.value.pool_name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.besu[each.value.region].id
  vm_size              = var.node_pools[each.value.pool_name].vm_size
  enable_auto_scaling   = true
  min_count            = var.node_pools[each.value.pool_name].min_count
  max_count            = var.node_pools[each.value.pool_name].max_count
  vnet_subnet_id       = azurerm_subnet.aks[each.value.region].id

  node_labels = {
    "nodepool"            = each.value.pool_name
    "besu-node-type"      = each.value.pool_name
    "region"             = each.value.region
  }

  tags = merge(var.tags, {
    NodePool = each.value.pool_name
  })
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "besu" {
  for_each = toset(local.regions)
  
  name                = "${var.cluster_prefix}-logs-${each.key}"
  resource_group_name = azurerm_resource_group.besu[each.key].name
  location           = azurerm_resource_group.besu[each.key].location
  sku               = "PerGB2018"
  retention_in_days  = var.monitoring.retention_days

  tags = var.tags
}

# Grant AKS managed identity access to Key Vault
resource "azurerm_key_vault_access_policy" "aks" {
  for_each = toset(local.regions)
  
  key_vault_id = azurerm_key_vault.besu[each.key].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.besu[each.key].identity[0].principal_id

  key_permissions = [
    "Get", "List"
  ]

  secret_permissions = [
    "Get", "List"
  ]

  certificate_permissions = [
    "Get", "List"
  ]
}

locals {
  regions = ["westeurope", "eastus"]
  node_pool_configs = flatten([
    for region in local.regions : [
      for pool_name in keys(var.node_pools) : {
        region     = region
        pool_name = pool_name
      }
    ]
  ])
}

data "azurerm_client_config" "current" {}

module "besu_network" {
  source = "./modules/besu-network"
  
  environment         = var.environment
  regions            = var.regions
  resource_group_prefix = var.resource_group_prefix
  cluster_prefix     = var.cluster_prefix
  node_pools         = var.node_pools
}

module "monitoring" {
  source = "./modules/monitoring"
  
  environment         = var.environment
  resource_group_prefix = var.resource_group_prefix
  log_analytics_workspace_name = var.log_analytics_workspace_name
}