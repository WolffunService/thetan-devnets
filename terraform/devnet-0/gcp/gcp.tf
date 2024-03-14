////////////////////////////////////////////////////////////////////////////////////////
//                                  TERRAFORM PROVIDERS
////////////////////////////////////////////////////////////////////////////////////////

provider "google" {
  project = var.google_cloud_project_name
  region  = var.google_cloud_project_region
}

////////////////////////////////////////////////////////////////////////////////////////
//                                        VARIABLES
////////////////////////////////////////////////////////////////////////////////////////

variable "google_cloud_project_name" {
  type = string
  description = "Google Cloud Project Name"
}

variable "google_cloud_project_region" {
  type    = string
  default = "asia-southeast1"
}

variable "google_ssh_key_name" {
  type    = string
  default = "shared-devops-eth2"
}

variable "google_ssh_key_login_username" {
  type    = string
  default = "devops"
}

variable "regions" {
  default = [
    "asia-southeast1-a",
  ]
}

locals {
  base_cidr_block = var.base_cidr_block
  google_vpcs = {
    for region in var.regions : region => {
      name     = "${var.ethereum_network}-${region}"
      region   = region
      ip_range = cidrsubnet(local.base_cidr_block, 8, index(var.regions, region))
    }
  }
}

locals {
  google_vm_groups = flatten([
    for vm_group in local.vm_groups :
    [
      for i in range(0, vm_group.count) : {
        group_name = "${vm_group.name}"
        id         = "${vm_group.name}-${i + 1}"
        vms = {
          "${i + 1}" = {
            tags   = "group-name--${vm_group.name},val-start--${vm_group.validator_start + (i * (vm_group.validator_end - vm_group.validator_start) / vm_group.count)},val-end--${min(vm_group.validator_start + ((i + 1) * (vm_group.validator_end - vm_group.validator_start) / vm_group.count), vm_group.validator_end)}"
            region = try(vm_group.location, local.google_default_region)
            size   = try(vm_group.size, local.google_default_size)
            ipv6   = try(vm_group.ipv6, false)
          }
        }
      }
    ]
  ])
}

locals {
  google_default_region = "asia-southeast1-a"
  google_default_size   = "e2-standard-2"
  google_default_image  = "debian-cloud/debian-12"
  google_global_tags = [
    "eth-network--${var.ethereum_network}"
  ]

  # flatten vm_groups so that we can use it with for_each()
  google_vms = flatten([
    for group in local.google_vm_groups : [
      for vm_key, vm in group.vms : {
        id        = "${group.id}"
        group_key = "${group.group_name}"
        vm_key    = vm_key

        name = try(vm.name, "${group.id}")
        region       = try(vm.region, try(group.region, local.google_default_region))
        image        = try(vm.image, local.google_default_image)
        size         = try(vm.size, local.google_default_size)
        resize_disk  = try(vm.resize_disk, true)
        monitoring   = try(vm.monitoring, true)
        backups      = try(vm.backups, false)
        ipv6         = try(vm.ipv6, false)
        ansible_vars = try(vm.ansible_vars, null)
        vpc_network_name = try(vm.vpc_network_name, try(
          google_compute_network.main[vm.region].name,
          google_compute_network.main[try(group.region, local.google_default_region)].name
        ))

        tags = concat(local.google_global_tags, try(split(",", group.tags), []), try(split(",", vm.tags), []))
      }
    ]
  ])
}

////////////////////////////////////////////////////////////////////////////////////////
//                                  GOOGLE CLOUD RESOURCES
////////////////////////////////////////////////////////////////////////////////////////

resource "google_compute_network" "main" {
  for_each = local.google_vpcs

  routing_mode = "REGIONAL"
  name         = each.value["name"]
  # region   = each.value["region"]
  # ip_range = each.value["ip_range"]
}

resource "google_compute_address" "main" {
  for_each = {
    for vm in local.google_vms : "${vm.id}" => vm
  }

  name = "${var.ethereum_network}-${each.value.name}"

  // cut string from "asia-southeast1-a" to "asia-southeast1"
  region = "${join("-", slice(split("-", each.value.region), 0, 2))}"
}

resource "google_compute_instance" "main" {
  for_each = {
    for vm in local.google_vms : "${vm.id}" => vm
  }

  name         = "${var.ethereum_network}-${each.value.name}"
  zone       = each.value.region
  machine_type = each.value.size
  tags         = each.value.tags

  metadata = {
    ssh-keys = "${var.google_ssh_key_login_username}:${tls_private_key.ssh.public_key_openssh}"
  }

  boot_disk {
    initialize_params {
      image = each.value.image
    }
  }

  network_interface {
    network = each.value.vpc_network_name

    access_config {
      nat_ip = google_compute_address.main[each.key].address
    }
  }

  # Don't restart the instance if it's terminated by Google
  # scheduling {
  #     preemptible = true
  #     automatic_restart = false
  # }
}

resource "google_compute_firewall" "main" {
  for_each = google_compute_network.main

  name          = "${var.ethereum_network}-nodes"
  network       = each.value.name
  target_tags   = [
    "eth-network--${var.ethereum_network}"
  ]

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22","80", "443", "9000-9002", "30303"]
  }

  allow {
    protocol = "udp"
    ports    = ["9000-9002"]
  }
}

////////////////////////////////////////////////////////////////////////////////////////
//                                   DNS NAMES
////////////////////////////////////////////////////////////////////////////////////////

data "cloudflare_zone" "default" {
  account_id = "501f6db1e29a7fc391c5f9efcdd387d4"
  name = "giangho.pro"
}

resource "cloudflare_record" "server_record" {
  for_each = {
    for vm in local.google_vms : "${vm.id}" => vm
  }
  zone_id = data.cloudflare_zone.default.id
  name    = "${each.value.name}.${var.ethereum_network}"
  type    = "A"
  value   = google_compute_address.main[each.value.id].address
  proxied = false
  ttl     = 120
  comment = "Node ${var.ethereum_network}: ${each.value.name}"
}

# resource "cloudflare_record" "server_record6" {
#   for_each = {
#     for vm in local.digitalocean_vms : "${vm.id}" => vm if vm.ipv6
#   }
#   zone_id = data.cloudflare_zone.default.id
#   name    = "${each.value.name}.${var.ethereum_network}"
#   type    = "AAAA"
#   value   = digitalocean_droplet.main[each.value.id].ipv6_address
#   proxied = false
#   ttl     = 120
# }

resource "cloudflare_record" "server_record_rpc" {
  for_each = {
    for vm in local.google_vms : "${vm.id}" => vm
  }
  zone_id = data.cloudflare_zone.default.id
  name    = "rpc.${each.value.name}.${var.ethereum_network}"
  type    = "A"
  value   = google_compute_address.main[each.value.id].address
  proxied = false
  ttl     = 120
  comment = "RPC ${var.ethereum_network}: ${each.value.name}"
}

# resource "cloudflare_record" "server_record_rpc6" {
#   for_each = {
#     for vm in local.digitalocean_vms : "${vm.id}" => vm if vm.ipv6
#   }
#   zone_id = data.cloudflare_zone.default.id
#   name    = "rpc.${each.value.name}.${var.ethereum_network}"
#   type    = "AAAA"
#   value   = digitalocean_droplet.main[each.value.id].ipv6_address
#   proxied = false
#   ttl     = 120
# }

resource "cloudflare_record" "server_record_beacon" {
  for_each = {
    for vm in local.google_vms : "${vm.id}" => vm
  }
  zone_id = data.cloudflare_zone.default.id
  name    = "bn.${each.value.name}.${var.ethereum_network}"
  type    = "A"
  value   = google_compute_address.main[each.value.id].address
  proxied = false
  ttl     = 120
  comment = "Beacon ${var.ethereum_network}: ${each.value.name}"
}

# resource "cloudflare_record" "server_record_beacon6" {
#   for_each = {
#     for vm in local.digitalocean_vms : "${vm.id}" => vm if vm.ipv6
#   }
#   zone_id = data.cloudflare_zone.default.id
#   name    = "bn.${each.value.name}.${var.ethereum_network}"
#   type    = "AAAA"
#   value   = digitalocean_droplet.main[each.value.id].ipv6_address
#   proxied = false
#   ttl     = 120
# }

////////////////////////////////////////////////////////////////////////////////////////
//                          GENERATED FILES AND OUTPUTS
////////////////////////////////////////////////////////////////////////////////////////

resource "local_file" "ansible_inventory" {
  content = templatefile("../ansible_inventory.tmpl",
    {
      ethereum_network_name = "${var.ethereum_network}"
      groups = merge(
        { for group in local.google_vm_groups : "${group.group_name}" => true... },
      )
      hosts = merge(
        {
          for key, server in google_compute_instance.main : "gcp.${key}" => {
            ip              = "${server.network_interface.0.access_config.0.nat_ip}"
            # ipv6            = try(server.ipv6_address, "none")
            ipv6            = "none"
            group           = try(split("--", tolist(server.tags)[1])[1], "unknown")
            validator_start = try(split("--", tolist(server.tags)[3])[1], 0)
            validator_end   = try(split("--", tolist(server.tags)[2])[1], 0) # if the tag is not a number it will be 0 - e.g no validator keys
            tags            = "${server.tags}"
            hostname        = "${split(".", key)[0]}"
            cloud           = "googleclould"
            region          = "${server.zone}"
          }
        }
      )
    }
  )
  filename = "../../../ansible/inventories/devnet-0/inventory.ini"
}
