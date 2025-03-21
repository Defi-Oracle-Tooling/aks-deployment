environment = "prod"

resource_group_prefix = "besu-network"
cluster_prefix       = "besu-aks"

regions = ["westeurope", "eastus"]

node_pools = {
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

monitoring = {
  retention_days = 30
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
  Network     = "Besu"
  CostCenter  = "Blockchain"
  Service     = "Besu-Network"
  Criticality = "High"
}

azure_key_vault = {
  sku              = "premium"
  soft_delete_days = 90
  purge_protection = true
}

alerts = {
  cpu_threshold    = 80
  memory_threshold = 85
  disk_threshold   = 80
  peer_count_min   = 3
}