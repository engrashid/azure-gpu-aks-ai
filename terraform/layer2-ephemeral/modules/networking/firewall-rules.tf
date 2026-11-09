# =============================================================================
# Firewall Rule Collection Group
#
# Priority 100 — AKS bootstrap (evaluated first)
#   network_rule_collection  : service-tag rules (non-HTTP/HTTPS)
#   application_rule_collection: required FQDNs for node bootstrap
#
# Priority 200 — Workload egress
#   application_rule_collection: HuggingFace, PyPI, NVIDIA, GitHub, etc.
#
# All source addresses are scoped to the Spoke VNet CIDR so only AKS nodes
# are covered. Azure Firewall's implicit default-deny drops everything else.
# =============================================================================

resource "azurerm_firewall_policy_rule_collection_group" "workload" {
  name               = "rcg-workload-egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 200

  # ── AKS bootstrap — network rules (service tags) ─────────────────────────────
  # These rules cover non-HTTP/HTTPS traffic that application rules cannot match.
  # Required by AKS with outbound_type=userDefinedRouting:
  #   TCP 9000 + UDP 1194  — API server tunnel (konnectivity / cloud-controller)
  #   TCP 443              — Azure Monitor, AAD, AzureCloud management
  #   UDP 123              — NTP time synchronisation (node bootstrap dependency)

  network_rule_collection {
    name     = "nrc-aks-bootstrap"
    priority = 100
    action   = "Allow"

    rule {
      name             = "allow-aks-api-tunnel"
      source_addresses = [var.spoke_vnet_cidr]
      # TCP 9000 + UDP 1194: konnectivity / cloud-controller tunnel
      # TCP 443: pods reach the API server via iptables DNAT (service IP 172.16.0.1 → public API
      #   server IP). TLS SNI is absent for IP-based connections, so the FQDN application rule
      #   cannot match — a network rule on port 443 is required.
      destination_ports     = ["443", "9000", "1194"]
      destination_addresses = ["AzureCloud.${var.location}"]
      protocols             = ["TCP", "UDP"]
    }

    rule {
      name                  = "allow-azure-monitor"
      source_addresses      = [var.spoke_vnet_cidr]
      destination_ports     = ["443"]
      destination_addresses = ["AzureMonitor"]
      protocols             = ["TCP"]
    }

    rule {
      name                  = "allow-azure-active-directory"
      source_addresses      = [var.spoke_vnet_cidr]
      destination_ports     = ["443"]
      destination_addresses = ["AzureActiveDirectory"]
      protocols             = ["TCP"]
    }

    rule {
      name                  = "allow-ntp"
      source_addresses      = [var.spoke_vnet_cidr]
      destination_ports     = ["123"]
      destination_addresses = ["*"]
      protocols             = ["UDP"]
    }
  }

  # ── AKS bootstrap — application rules (FQDNs) ────────────────────────────────
  # Required outbound FQDNs per https://aka.ms/aks-required-ports-and-addresses
  # All on HTTPS/443 unless noted.

  application_rule_collection {
    name     = "arc-aks-bootstrap"
    priority = 150
    action   = "Allow"

    rule {
      name              = "allow-aks-api-server"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["*.hcp.${var.location}.azmk8s.io"]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "allow-azure-management"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["management.azure.com"]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "allow-azure-ad"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["login.microsoftonline.com"]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "allow-microsoft-packages"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["packages.microsoft.com", "acs-mirror.azureedge.net"]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "allow-mcr-data"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["*.data.mcr.microsoft.com", "*.cdn.mscr.io"]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "allow-log-analytics"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
        "*.monitoring.azure.com",
        "dc.services.visualstudio.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  # ── Workload egress — application rules ──────────────────────────────────────

  application_rule_collection {
    name     = "arc-workload-allow"
    priority = 200
    action   = "Allow"

    # ── AI / ML ────────────────────────────────────────────────────────────────

    rule {
      name              = "allow-huggingface"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["huggingface.co", "*.huggingface.co"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Azure PaaS ──────────────────────────────────────────────────────────────

    rule {
      name              = "allow-azure-blob-storage"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["*.blob.core.windows.net"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "allow-container-registries"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["*.azurecr.io", "mcr.microsoft.com"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Python package index ────────────────────────────────────────────────────

    rule {
      name              = "allow-pypi"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["pypi.org", "*.pypi.org", "files.pythonhosted.org"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── NVIDIA drivers / libraries ──────────────────────────────────────────────

    rule {
      name             = "allow-nvidia"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "nvidia.github.io",
        "*.nvidia.com",
        "developer.download.nvidia.com",
        "nvcr.io",
        "*.nvcr.io",
      ]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Ubuntu package mirrors ──────────────────────────────────────────────────

    rule {
      name             = "allow-ubuntu"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "*.ubuntu.com",
        "security.ubuntu.com",
        "archive.ubuntu.com",
      ]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── GitHub ──────────────────────────────────────────────────────────────────

    rule {
      name             = "allow-github"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "github.com",
        "api.github.com",
        "raw.githubusercontent.com",
        "objects.githubusercontent.com",
        "*.githubusercontent.com",
        "*.github.io",
        # GitHub Container Registry
        "ghcr.io",
        "pkg.github.com",
      ]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Let's Encrypt ACME ─────────────────────────────────────────────────────
    # cert-manager registers with ACME and fetches challenges via these endpoints.

    rule {
      name             = "allow-letsencrypt"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "acme-v02.api.letsencrypt.org",
        "acme-staging-v02.api.letsencrypt.org",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── cert-manager HTTP-01 self-check ─────────────────────────────────────────
    # cert-manager verifies the ACME HTTP-01 challenge internally before asking
    # Let's Encrypt to validate. It resolves the public hostname (chat.*) and makes
    # an HTTP request that goes pod → UDR → Firewall → App Gateway public IP.
    # Without this rule the Firewall denies with 470 and cert-manager never proceeds.

    rule {
      name              = "allow-chat-self-check"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["chat.${var.public_domain}"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "allow-argocd-self-check"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["argocd.${var.public_domain}"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Helm chart repository ───────────────────────────────────────────────────

    rule {
      name             = "allow-helm"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "charts.helm.sh",
        "charts.jetstack.io", # cert-manager
      ]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Azure DevOps ────────────────────────────────────────────────────────────

    rule {
      name             = "allow-azure-devops"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "dev.azure.com",
        "*.dev.azure.com",
        "*.visualstudio.com",
      ]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Docker Hub ──────────────────────────────────────────────────────────────

    rule {
      name             = "allow-docker-hub"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "registry-1.docker.io",
        "*.docker.io",
        "auth.docker.io",
      ]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Quay.io ─────────────────────────────────────────────────────────────────

    rule {
      name              = "allow-quay"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["quay.io", "*.quay.io"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Kubernetes image registries ─────────────────────────────────────────────

    rule {
      name             = "allow-kubernetes-registries"
      source_addresses = [var.spoke_vnet_cidr]
      # registry.k8s.io redirects blobs to Google AR (*.pkg.dev) or AWS S3 (*.amazonaws.com)
      # depending on the region/CDN selected at pull time.
      destination_fqdns = ["k8s.gcr.io", "registry.k8s.io", "*.pkg.dev", "*.amazonaws.com"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── AWS ECR Public ──────────────────────────────────────────────────────────
    # ArgoCD 9.x ships Redis from ecr-public.aws.com. Manifests resolve via
    # ecr-public.aws.com / public.ecr.aws; blobs are served via CloudFront.

    rule {
      name              = "allow-ecr-public"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["ecr-public.aws.com", "public.ecr.aws"]
      protocols {
        type = "Https"
        port = 443
      }
    }

    # ── Container image blob CDNs ────────────────────────────────────────────────
    # Registry manifests are served by the registry FQDN (already allowed above),
    # but image layer blobs are redirected to CDNs:
    #   Docker Hub   → *.r2.cloudflarestorage.com  (Cloudflare R2)
    #   ECR Public   → *.cloudfront.net             (AWS CloudFront)
    # Without these rules containerd cannot download image layers.

    rule {
      name             = "allow-dockerhub-blob-cdn"
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "*.r2.cloudflarestorage.com",
        "production.cloudflare.docker.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "allow-ecr-public-blob-cdn"
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["*.cloudfront.net"]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}
