variable "ssh_public_key" {
  type        = string
  description = "SSH public Key for admin user"
}

variable "name" {
  description = "Host name"
  type        = string
  default     = "hetzvpn"
}

variable "ssh_port" {
  description = "SSH port"
  type        = number
  default     = 22
}

variable "vpn_port" {
  description = "VPN port"
  type        = number
  default     = 51820
}

variable "location" {
  description = "The server location"
  type        = string
}

variable "dns_servers" {
  type        = list(string)
  description = "IP Addresses to use for the DNS Servers, set to an empty list to use the ones provided by Hetzner"
  default     = ["1.1.1.1", "8.8.8.8", "2606:4700:4700::1111"]
}

variable "ssh_allowed_ips" {
  type        = list(string)
  description = "IP Addresses allowed to connect to the SSH port"
  default     = ["0.0.0.0/0", "::/0"]
}

variable "vpn_allowed_ips" {
  type        = list(string)
  description = "IP Addresses allowed to connect to the VPN port"
  default     = ["0.0.0.0/0", "::/0"]
}

variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

variable "instance_type" {
  type        = string
  description = "Hetzner Cloud instance type"
  default     = "cpx11"
}

locals {
  # Hetzner datacenter mappings
  datacenter_config = {
    "ash" = { # Ashburn, VA
      timezone     = "America/New_York"
    }
    "hil" = { # Hillsboro, OR
      timezone     = "America/Los_Angeles"
    }
    "fsn1" = { # Falkenstein, Germany
      timezone     = "Europe/Berlin"
    }
    "nbg1" = { # Nuremberg, Germany
      timezone     = "Europe/Berlin"
    }
    "hel1" = { # Helsinki, Finland
      timezone     = "Europe/Helsinki"
    }
    "sin" = { # Singapore
      timezone     = "Asia/Singapore"
    }
  }

  dc_config = local.datacenter_config[var.location]
}

resource "hcloud_ssh_key" "admin" {
  name       = "hetzvpn-admin"
  public_key = var.ssh_public_key
  labels     = { "createdby" : "hetzvpn-terraform" }
  lifecycle {
    ignore_changes = [
      public_key
    ]
  }
}

resource "hcloud_firewall" "main" {
  name = "main"
  rule {
    description = "Allow Incoming SSH Traffic"
    direction   = "in"
    protocol    = "tcp"
    port        = var.ssh_port
    source_ips  = var.ssh_allowed_ips
  }
  rule {
    description = "Allow Incoming VPN Traffic"
    direction   = "in"
    protocol    = "udp"
    port        = var.vpn_port
    source_ips  = var.vpn_allowed_ips
  }
  rule {
    description = "Allow Incoming ICMP Ping Requests"
    direction   = "in"
    protocol    = "icmp"
    port        = ""
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description     = "Allow Outbound ICMP Ping Requests"
    direction       = "out"
    protocol        = "icmp"
    port            = ""
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description     = "Allow All Outbound TCP Traffic"
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description     = "Allow All Outbound UDP Traffic"
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# for temp ssh key file
resource "random_string" "identity_file" {
  length  = 20
  lower   = true
  special = false
  numeric = true
  upper   = false
}

resource "hcloud_server" "server" {
  name               = var.name
  image              = "alma-9"
  server_type        = var.instance_type
  location           = var.location
  firewall_ids       = [hcloud_firewall.main.id]
  user_data          = data.cloudinit_config.config.rendered
  ssh_keys           = [hcloud_ssh_key.admin.id]
  labels             = { "createdby" : "hetzvpn-terraform" }

  # Avoid recreating the server for these, should change these manually (ansible, etc)
  lifecycle {
    ignore_changes = [
      user_data,
      image,
      ssh_keys
    ]
  }

  # Prepare ssh identity file (needed for ssh in terraform)
  provisioner "local-exec" {
    command = <<-EOT
      install -b -m 600 /dev/null /tmp/${random_string.identity_file.id}
      echo "${var.ssh_public_key}" | sed 's/\r$//' > /tmp/${random_string.identity_file.id}
    EOT
  }

  # Reset host keys
  provisioner "local-exec" {
    command = <<-EOT
      ssh-keygen -R ${self.ipv4_address} || true
      ssh -o StrictHostKeyChecking=no -i /tmp/${random_string.identity_file.id} -p ${var.ssh_port} admin@${self.ipv4_address} exit
    EOT
  }

  # Wait for cloud-init
  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..60}; do
        status=$(ssh -i /tmp/${random_string.identity_file.id} -p ${var.ssh_port} admin@${self.ipv4_address} sudo cloud-init status)
        if echo "$status" | grep -q "done"; then
          echo "Cloud-init finished successfully"
          exit 0
        elif echo "$status" | grep -q "error"; then
          echo "Cloud-init failed with error:"
          ssh -i /tmp/${random_string.identity_file.id} -p ${var.ssh_port} admin@${self.ipv4_address} sudo cloud-init status -l
          exit 1
        fi
        echo "Waiting for cloud-init to finish... (attempt $i/60)"
        sleep 10
      done
      echo "Timeout waiting for cloud-init to finish"
      exit 1
    EOT
  }

  # Reboot after successful cloud-init
  provisioner "local-exec" {
    command = <<-EOT
      echo "Rebooting server..."
      ssh -i /tmp/${random_string.identity_file.id} -p ${var.ssh_port} admin@${self.ipv4_address} sudo reboot
      
      # Wait for server to come back up
      echo "Waiting for server to come back online..."
      sleep 10
      for i in {1..30}; do
        if ssh -i /tmp/${random_string.identity_file.id} -p ${var.ssh_port} admin@${self.ipv4_address} exit; then
          echo "Server is back online"
          exit 0
        fi
        echo "Still waiting for server... (attempt $i/30)"
        sleep 10
      done
      echo "Timeout waiting for server to come back online"
      exit 1
    EOT
  }

  # Cleanup ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      rm /tmp/${random_string.identity_file.id}
    EOT
  }
}

data "cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/cloudinit.yaml.tpl",
      {
        hostname               = var.name
        ssh_port               = var.ssh_port
        ssh_public_key         = var.ssh_public_key
        tz                     = local.dc_config.timezone
        vpn_port               = var.vpn_port
      }
    )
  }
}

terraform {
  backend "local" {}
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.51.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

output "public_ipv4" {
  value = hcloud_server.server.ipv4_address
}

output "public_ipv6" {
  value = hcloud_server.server.ipv6_address
}

output "id" {
  value = hcloud_server.server.id
}

output "name" {
  value = hcloud_server.server.name
}

output "vpn_port" {
  value = var.vpn_port
}

output "ssh_port" {
  value = var.ssh_port
}