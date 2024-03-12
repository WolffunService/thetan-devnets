terraform {
  backend "gcs" {
    bucket = "thetan-chain-devnet"
    prefix = "devnet-0"
  }
}
