environment = "production"
network_type = "mainnet"

resource_group_prefix = "besu-network"
cluster_prefix       = "besu-aks"

regions = ["westeurope", "eastus"]

node_pools = {
  validator = {
    vm_size   = "Standard_D16s_v4"
    min_count = 7
    max_count = 14
  }
  bootnode = {
    vm_size   = "Standard_E16s_v4"
    min_count = 4
    max_count = 7
  }
  rpc = {
    vm_size   = "Standard_E16s_v5"
    min_count = 4
    max_count = 7
  }
}

monitoring = {
  retention_days = 90
  alerts_enabled = true
}

network = {
  vnet_cidr     = "10.0.0.0/16"
  subnet_cidrs = {
    aks     = "10.0.1.0/24"
  }
}

tags = {
  Environment = "Production"
  ManagedBy   = "Terraform"
  Network     = "Defi Oracle Meta Mainnet"
  CostCenter  = "Blockchain-Prod"
  Service     = "Besu-Network"
  Criticality = "High"
}

azure_key_vault = {
  sku              = "premium"
  soft_delete_days = 90
  purge_protection = true
}

alerts = {
  cpu_threshold    = 85
  memory_threshold = 90
  disk_threshold   = 85
  peer_count_min   = 5
}