////////////////////////////////////////////////////////////////////////////////////////
//                                  TERRAFORM PROVIDERS
////////////////////////////////////////////////////////////////////////////////////////

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

////////////////////////////////////////////////////////////////////////////////////////
//                                        VARIABLES
////////////////////////////////////////////////////////////////////////////////////////

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API Token"
}

variable "ethereum_network" {
  type    = string
  default = "devnet-0"
}

variable "base_cidr_block" {
  default = "10.76.0.0/16"
}

////////////////////////////////////////////////////////////////////////////////////////
//                                        LOCALS
////////////////////////////////////////////////////////////////////////////////////////

locals {
  vm_groups = [
    var.bootnode,
    var.lighthouse_geth,
    var.lighthouse_nethermind,
    # var.lighthouse_erigon,
    # var.lighthouse_besu,
    # var.lighthouse_ethereumjs,
    # var.lighthouse_reth,
    var.prysm_geth,
    var.prysm_nethermind,
    # var.prysm_erigon,
    # var.prysm_besu,
    # var.prysm_ethereumjs,
    # var.prysm_reth,
    # var.lodestar_geth,
    # var.lodestar_nethermind,
    # var.lodestar_erigon,
    # var.lodestar_besu,
    # var.lodestar_ethereumjs,
    # var.lodestar_reth,
    # var.nimbus_geth,
    # var.nimbus_nethermind,
    # var.nimbus_erigon,
    # var.nimbus_besu,
    # var.nimbus_ethereumjs,
    # var.nimbus_reth,
    # var.teku_geth,
    # var.teku_nethermind,
    # var.teku_erigon,
    # var.teku_besu,
    # var.teku_ethereumjs,
    # var.teku_reth,
  ]
}
