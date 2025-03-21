variable "environment" {
  description = "Environment name (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

variable "resource_group_prefix" {
  description = "Prefix for resource group names"
  type        = string
  default     = "besu-network"
}

variable "cluster_prefix" {
  description = "Prefix for AKS cluster names"
  type        = string
  default     = "besu-aks"
}

variable "regions" {
  description = "List of Azure regions to deploy to"
  type        = list(string)
  default     = ["westeurope", "eastus"]
}

variable "network" {
  description = "Network configuration"
  type = object({
    vnet_cidr = string
    subnet_cidrs = object({
      aks = string
    })
  })
  default = {
    vnet_cidr = "10.0.0.0/16"
    subnet_cidrs = {
      aks = "10.0.1.0/24"
    }
  }
}

variable "node_pools" {
  description = "Configuration for AKS node pools"
  type = map(object({
    vm_size   = string
    min_count = number
    max_count = number
  }))
  default = {
    validator = {
      vm_size   = "Standard_D8s_v3"
      min_count = 3
      max_count = 5
    }
    bootnode = {
      vm_size   = "Standard_D4s_v3"
      min_count = 2
      max_count = 3
    }
    rpc = {
      vm_size   = "Standard_D4s_v3"
      min_count = 2
      max_count = 4
    }
  }
}

variable "monitoring" {
  description = "Monitoring configuration"
  type = object({
    retention_days = number
    alerts_enabled = bool
  })
  default = {
    retention_days = 30
    alerts_enabled = true
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Network     = "Besu"
    CostCenter  = "Blockchain"
  }
}

variable "azure_key_vault" {
  description = "Azure Key Vault configuration"
  type = object({
    sku                 = string
    soft_delete_days    = number
    purge_protection    = bool
  })
  default = {
    sku                 = "premium"
    soft_delete_days    = 90
    purge_protection    = true
  }
}

variable "alerts" {
  description = "Alert configuration for monitoring"
  type = object({
    cpu_threshold     = number
    memory_threshold  = number
    disk_threshold    = number
    peer_count_min    = number
  })
  default = {
    cpu_threshold     = 80
    memory_threshold  = 85
    disk_threshold    = 80
    peer_count_min    = 3
  }
}