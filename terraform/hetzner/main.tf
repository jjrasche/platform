terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

variable "hcloud_token" {
  sensitive = true
}

provider "hcloud" {
  token = var.hcloud_token
}

# --- VPS ---

resource "hcloud_ssh_key" "deploy" {
  name       = "platform-deploy"
  public_key = file("~/.ssh/id_platform.pub")
}

resource "hcloud_firewall" "platform" {
  name = "platform"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "platform" {
  name        = "platform"
  server_type = "cx22"
  image       = "ubuntu-24.04"
  location    = "ash"
  ssh_keys    = [hcloud_ssh_key.deploy.id]
  firewall_ids = [hcloud_firewall.platform.id]
}

# --- Object Storage for backups ---
# Hetzner Object Storage is managed via S3 API, not Terraform.
# Create manually: hcloud object-storage create --name jmr-backups

output "server_ip" {
  value = hcloud_server.platform.ipv4_address
}
