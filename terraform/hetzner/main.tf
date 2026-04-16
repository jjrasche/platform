terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

variable "hcloud_token" {
  sensitive = true
}

variable "cloudflare_api_token" {
  sensitive = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for jimr.fyi"
}

variable "ssh_allowed_ipv4" {
  description = "IPv4 CIDRs allowed to SSH (admin IPs). Empty list falls back to 0.0.0.0/0."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_ipv6" {
  description = "IPv6 CIDRs allowed to SSH. Empty list falls back to ::/0."
  type        = list(string)
  default     = []
}

locals {
  ssh_source_ips = concat(
    length(var.ssh_allowed_ipv4) > 0 ? var.ssh_allowed_ipv4 : ["0.0.0.0/0"],
    length(var.ssh_allowed_ipv6) > 0 ? var.ssh_allowed_ipv6 : ["::/0"],
  )

  # Cloudflare IP ranges — https://www.cloudflare.com/ips/
  # Last verified: 2026-04-16
  cloudflare_ipv4 = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
  cloudflare_ipv6 = [
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ]
  cloudflare_ips = concat(local.cloudflare_ipv4, local.cloudflare_ipv6)
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# --- VPS1 (platform) ---

resource "hcloud_ssh_key" "deploy" {
  name       = "platform-deploy"
  public_key = file("~/.ssh/id_platform.pub")
}

resource "hcloud_firewall" "platform" {
  name = "platform"

  # Hetzner firewalls are default-deny: unlisted ports are blocked.
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = local.ssh_source_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = local.cloudflare_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = local.cloudflare_ips
  }
}

resource "hcloud_server" "platform" {
  name        = "platform"
  server_type = "cax21"
  image       = "ubuntu-24.04"
  location    = "fsn1"
  ssh_keys    = [hcloud_ssh_key.deploy.id]
  firewall_ids = [hcloud_firewall.platform.id]
}

# --- Object Storage for backups ---
# Hetzner Object Storage is managed via S3 API, not Terraform.
# Create manually: hcloud object-storage create --name jmr-backups

# --- Cloudflare zone-level security ---
# Zone-wide settings for jimr.fyi. Benefits all subdomains.

resource "cloudflare_zone_settings_override" "jimr_fyi" {
  zone_id = var.cloudflare_zone_id

  settings {
    ssl                      = "strict"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"

    security_header {
      enabled            = true
      include_subdomains = true
      max_age            = 31536000
      nosniff            = true
      preload            = true
    }
  }
}

# --- Outputs ---

output "server_ip" {
  value = hcloud_server.platform.ipv4_address
}

output "platform_firewall_id" {
  value = hcloud_firewall.platform.id
}
