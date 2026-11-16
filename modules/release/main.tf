# A second Reducto release on an existing cluster, bound to one tenant.
#
# The root module deploys the shared cluster: network, GKE, KEDA, Cloud SQL,
# one bucket, one Google service account with an HMAC key, and the `reducto`
# Helm release. Every tenant that calls that release shares its storage
# identity, so a bug or a compromise in one request path can reach any
# tenant's bucket.
#
# This module adds a release that belongs to one tenant: its own namespace,
# its own Kubernetes service account bound through Workload Identity to a
# Google service account the tenant owns, the tenant's bucket as the only
# BUCKET, its own database, optional API-key authentication, and its own
# internal load balancer for a Private Service Connect attachment. No HMAC key
# is created or injected: GCS writes use the pod identity, which is what
# Reducto recommends for a per-tenant namespace.
#
# Providers: pass `helm` and `kubectl` configured for the cluster the root
# module created. The Workload Identity IAM binding on the Google service
# account is the caller's: grant roles/iam.workloadIdentityUser to the member
# this module outputs.

terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.43.0, < 8"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

locals {
  # The chart names its ServiceAccount and HTTP Service after the release.
  kubernetes_service_account_name = "${var.release_name}-reducto"
  http_service_name               = "${var.release_name}-reducto-http"
  backend_config_name             = "${var.release_name}-backendconfig"
  workload_identity_member        = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${local.kubernetes_service_account_name}]"

  auth_enabled = nonsensitive(var.api_key != "")

  sensitive_env = merge(
    {
      GCP_API_KEY  = google_apikeys_key.vision.key_string
      DATABASE_URL = var.database_url
    },
  )
}

resource "random_string" "api_key_name_suffix" {
  length  = 4
  special = false
  lower   = true
  upper   = false
}

# Cloud Vision OCR authenticates with an API key, not the pod identity. One key
# per release so a tenant's key can be rotated or revoked on its own.
resource "google_apikeys_key" "vision" {
  name         = "${var.release_name}-${random_string.api_key_name_suffix.result}"
  display_name = "Reducto Cloud Vision Key (${var.release_name})"
  project      = var.project_id

  # The key leaves Terraform as a pod env var; limit what it is good for.
  restrictions {
    api_targets {
      service = "vision.googleapis.com"
    }
  }
}

resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.namespace
      labels = {
        "reducto.rogo.ai/release" = var.release_name
      }
    }
  })
}

resource "kubectl_manifest" "backend_config" {
  count = var.enable_global_access ? 0 : 1

  yaml_body = yamlencode({
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      namespace = var.namespace
      name      = local.backend_config_name
    }
    spec = {
      timeoutSec         = 900
      connectionDraining = { drainingTimeoutSec = 300 }
    }
  })

  depends_on = [kubectl_manifest.namespace]
}

resource "helm_release" "reducto" {
  namespace        = var.namespace
  name             = var.release_name
  create_namespace = false

  repository_username = var.reducto_helm_repo_username
  repository_password = var.reducto_helm_repo_password

  chart   = var.reducto_helm_chart_oci
  version = var.reducto_helm_chart_version
  wait    = false

  values = concat(
    [
      templatefile("${path.module}/values/reducto.yaml.tftpl", {
        min_replica_count = var.reducto_worker_min_replica_count
        max_replica_count = var.reducto_worker_max_replica_count
      }),
      yamlencode({
        ingress = { enabled = !var.enable_global_access }
      }),
      yamlencode({
        env = merge(
          {
            GCP_PROJECT_ID            = var.gcp_project_id
            GCP_REGION                = var.vertex_ai_region
            BUCKET                    = var.bucket_name
            GCP_SERVICE_ACCOUNT_EMAIL = var.gcp_service_account_email
          },
          var.otel_exporter_otlp_endpoint != "" ? { OTEL_EXPORTER_OTLP_ENDPOINT = var.otel_exporter_otlp_endpoint } : {},
          var.extra_env,
        )
      }),
    ],
    var.enable_global_access ? [] : [
      yamlencode({
        http = {
          service = {
            annotations = {
              "cloud.google.com/backend-config" = jsonencode({ ports = { "80" = local.backend_config_name } })
            }
          }
        }
      })
    ],
    local.auth_enabled ? [
      yamlencode({
        auth = {
          secretPath = {
            enabled      = true
            createSecret = true
            secretName   = "${var.release_name}-api-keys"
          }
        }
      })
    ] : [],
  )

  set_sensitive = [
    for name, value in merge(
      local.sensitive_env,
      local.auth_enabled ? { "__auth" = var.api_key } : {},
      ) : {
      # The provider hands "name=value" to Helm's --set parser unescaped, so
      # escape backslashes first, then commas (value separator) and "{" (a
      # leading "{" is parsed as a list).
      name  = name == "__auth" ? "auth.secretPath.apiKey" : "env.${name}"
      value = replace(replace(replace(value, "\\", "\\\\"), ",", "\\,"), "{", "\\{")
      type  = "string"
    }
  ]

  depends_on = [
    kubectl_manifest.namespace,
    kubectl_manifest.backend_config,
  ]
}

# The chart creates the Kubernetes service account; Workload Identity needs the
# GSA annotation on it. Server-side apply with its own field manager so Helm
# keeps owning the rest of the object.
resource "kubectl_manifest" "workload_identity_annotation" {
  server_side_apply = true
  apply_only        = true
  field_manager     = "reducto-workload-identity"

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      namespace = var.namespace
      name      = local.kubernetes_service_account_name
      annotations = {
        "iam.gke.io/gcp-service-account" = var.gcp_service_account_email
      }
    }
  })

  depends_on = [helm_release.reducto]
}

# ------------------------------------------------------------------------------
# Internal load balancer with global access (Gateway API), one per release, so
# the PSC producer can attach a tenant-specific service attachment to it.
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "gateway" {
  count = var.enable_global_access ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "${var.release_name}-gateway"
      namespace = var.namespace
    }
    spec = {
      gatewayClassName = "gke-l7-rilb"
      listeners = [{
        name     = "http"
        protocol = "HTTP"
        port     = 80
      }]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}

resource "kubectl_manifest" "gateway_policy" {
  count = var.enable_global_access ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "GCPGatewayPolicy"
    metadata = {
      name      = "${var.release_name}-gateway-policy"
      namespace = var.namespace
    }
    spec = {
      default = { allowGlobalAccess = true }
      targetRef = {
        group = "gateway.networking.k8s.io"
        kind  = "Gateway"
        name  = "${var.release_name}-gateway"
      }
    }
  })

  depends_on = [kubectl_manifest.gateway]
}

resource "kubectl_manifest" "http_route" {
  count = var.enable_global_access ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${var.release_name}-route"
      namespace = var.namespace
    }
    spec = {
      parentRefs = [{ kind = "Gateway", name = "${var.release_name}-gateway" }]
      rules = [{
        backendRefs = [{ name = local.http_service_name, port = 80 }]
      }]
    }
  })

  depends_on = [kubectl_manifest.gateway, helm_release.reducto]
}

resource "kubectl_manifest" "backend_policy" {
  count = var.enable_global_access ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "GCPBackendPolicy"
    metadata = {
      name      = "${var.release_name}-backend-policy"
      namespace = var.namespace
    }
    spec = {
      default = {
        timeoutSec         = 900
        connectionDraining = { drainingTimeoutSec = 300 }
      }
      targetRef = {
        group = ""
        kind  = "Service"
        name  = local.http_service_name
      }
    }
  })

  depends_on = [helm_release.reducto]
}
