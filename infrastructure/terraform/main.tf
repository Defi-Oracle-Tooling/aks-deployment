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
    key                  = "besu.tfstate"
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
  location            = azurerm_resource_group.besu[each.key].location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"

  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
  soft_delete_retention_days  = 90

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.aks[each.key].id]
  }

  tags = var.tags
}

# Create virtual networks for each region
resource "azurerm_virtual_network" "besu" {
  for_each = toset(local.regions)
  
  name                = "${var.resource_group_prefix}-vnet-${each.key}"
  resource_group_name = azurerm_resource_group.besu[each.key].name
  location            = azurerm_resource_group.besu[each.key].location
  address_space       = [var.network.vnet_cidr]
  
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
  location            = azurerm_resource_group.besu[each.key].location
  resource_group_name = azurerm_resource_group.besu[each.key].name
  dns_prefix          = "${var.cluster_prefix}-${each.key}"
  kubernetes_version  = "1.25.6"

  default_node_pool {
    name                = "system"
    vm_size             = local.network_config.vm_sizes.validator
    min_count           = 1
    max_count           = 3
    vnet_subnet_id      = azurerm_subnet.aks[each.key].id

    node_labels = {
      "role" = "system"
      "network.besu.hyperledger.org/chainId" = local.network_config.chain_id
    }
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
  }

  auto_scaler_profile {
    scale_down_delay_after_add   = "10m"
    scale_down_unneeded          = "10m"
    max_graceful_termination_sec = "600"
  }

  role_based_access_control_enabled = true
  azure_policy_enabled              = true
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.besu[each.key].id
  }

  tags = local.common_tags
}

# Create node pools for Besu nodes
resource "azurerm_kubernetes_cluster_node_pool" "besu" {
  for_each = {
    for pair in local.node_pool_configs : "${pair.region}-${pair.pool_name}" => merge(pair, {
      vm_size = local.node_pools[pair.pool_name].vm_size
      min_count = local.node_pools[pair.pool_name].min_count
      max_count = local.node_pools[pair.pool_name].max_count
      node_labels = local.node_pools[pair.pool_name].node_labels
      node_taints = lookup(local.node_pools[pair.pool_name], "node_taints", [])
    })
  }

  name                  = each.value.pool_name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.besu[each.value.region].id
  vm_size              = each.value.vm_size
  min_count            = each.value.min_count
  max_count            = each.value.max_count
  vnet_subnet_id       = azurerm_subnet.aks[each.value.region].id

  node_labels = merge(each.value.node_labels, {
    "region"              = each.value.region
    "network.type"        = var.network_type
    "besu-node-type"      = each.value.pool_name
  })

  node_taints = each.value.node_taints

  tags = merge(local.common_tags, {
    NodePool = each.value.pool_name
    Region   = each.value.region
  })
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "besu" {
  for_each = toset(local.regions)
  
  name                = "${var.cluster_prefix}-logs-${each.key}"
  resource_group_name = azurerm_resource_group.besu[each.key].name
  location            = azurerm_resource_group.besu[each.key].location
  sku                 = "PerGB2018"
  retention_in_days   = var.monitoring.retention_days

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
        pool_name  = pool_name
      }
    ]
  ])

  network_config = {
    chain_id     = var.chain_id[var.network_type]
    network_name = var.network_name[var.network_type]
    min_nodes    = var.min_nodes[var.network_type]
    vm_sizes     = var.vm_sizes[var.network_type]
  }

  node_pools = {
    validator = {
      name                = "validator"
      vm_size            = local.network_config.vm_sizes.validator
      min_count          = local.network_config.min_nodes
      max_count          = local.network_config.min_nodes * 2
      node_labels = {
        "role" = "validator"
        "network.besu.hyperledger.org/chainId" = local.network_config.chain_id
      }
      node_taints = ["role=validator:NoSchedule"]
    }
    bootnode = {
      name                = "bootnode"
      vm_size            = local.network_config.vm_sizes.bootnode
      min_count          = max(local.network_config.min_nodes / 2, 1)
      max_count          = local.network_config.min_nodes
      node_labels = {
        "role" = "bootnode"
        "network.besu.hyperledger.org/chainId" = local.network_config.chain_id
      }
    }
    rpc = {
      name                = "rpc"
      vm_size            = local.network_config.vm_sizes.rpc
      min_count          = max(local.network_config.min_nodes / 2, 1)
      max_count          = local.network_config.min_nodes
      node_labels = {
        "role" = "rpc"
        "network.besu.hyperledger.org/chainId" = local.network_config.chain_id
      }
    }
  }

  common_tags = merge(var.tags, {
    NetworkType = var.network_type
    ChainId     = local.network_config.chain_id
    NetworkName = local.network_config.network_name
  })
}

data "azurerm_client_config" "current" {}

module "besu_network" {
  source = "./modules/besu-network"
  
  environment           = var.environment
  regions               = var.regions
  resource_group_prefix = var.resource_group_prefix
  cluster_prefix        = var.cluster_prefix
  node_pools            = var.node_pools
}

module "monitoring" {
  source = "./modules/monitoring"
  
  environment                  = var.environment
  resource_group_prefix        = var.resource_group_prefix
  log_analytics_workspace_name = var.log_analytics_workspace_name
}