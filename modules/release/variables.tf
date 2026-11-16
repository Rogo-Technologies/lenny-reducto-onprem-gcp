variable "project_id" {
  type        = string
  description = "Project that owns the GKE cluster this release runs in (Vision API key and Workload Identity pool live here)."
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for this release. Created by the module. One tenant per namespace."
}

variable "release_name" {
  type        = string
  description = "Helm release name. The chart derives the service account (`<release>-reducto`) and HTTP service (`<release>-reducto-http`) from it."
}

variable "gcp_service_account_email" {
  type        = string
  description = "Google service account the pods run as through Workload Identity. Owned and bound by the caller (it may live in another project); this module only annotates the Kubernetes service account."
}

variable "gcp_project_id" {
  type        = string
  description = "Project Reducto uses for Vertex AI and Vision calls (GCP_PROJECT_ID). Usually the tenant project that owns the service account and bucket."
}

variable "bucket_name" {
  type        = string
  description = "GCS bucket for intermediate results (BUCKET). Must exist; the service account needs roles/storage.objectAdmin on it."
}

variable "database_url" {
  type        = string
  sensitive   = true
  description = "Postgres connection URL for this release. Give each release its own database."
}

variable "vertex_ai_region" {
  type        = string
  default     = ""
  description = "GCP_REGION for Vertex AI; empty means the global endpoint."
}

variable "api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "When set, enables the chart's API-key authentication (auth.secretPath) with this single key, so only callers that hold it can use the release."
}

variable "reducto_helm_chart_oci" {
  type    = string
  default = "oci://registry.reducto.ai/reducto-api/reducto"
}

variable "reducto_helm_chart_version" {
  type = string
}

variable "reducto_helm_repo_username" {
  type      = string
  sensitive = true
}

variable "reducto_helm_repo_password" {
  type      = string
  sensitive = true
}

variable "reducto_worker_min_replica_count" {
  type    = number
  default = 2
}

variable "reducto_worker_max_replica_count" {
  type    = number
  default = 20
}

variable "enable_global_access" {
  type        = bool
  default     = true
  description = "Expose the release through a Gateway API internal load balancer with global access (the shape the PSC producer expects). When false, the chart's gce-internal Ingress is used instead."
}

variable "otel_exporter_otlp_endpoint" {
  type        = string
  default     = ""
  description = "OTLP endpoint for traces/metrics, e.g. the cluster's Datadog agent. Empty disables."
}

variable "extra_env" {
  type        = map(string)
  default     = {}
  description = "Additional non-secret environment variables for the chart."
}
