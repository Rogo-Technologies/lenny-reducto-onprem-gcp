variable "enable_workload_identity" {
  type        = bool
  default     = false
  description = "Prepare the IAM binding and annotate the existing Reducto Kubernetes service account. Apply this before switching credentials."
}

variable "use_workload_identity_credentials" {
  type        = bool
  default     = false
  description = "Stop injecting GOOGLE_APPLICATION_CREDENTIALS after the prepared Kubernetes identity has been verified. The existing key is retained until a separate retirement change."
}

variable "workload_identity_service_account_name" {
  type        = string
  default     = "reducto-reducto"
  description = "Existing Kubernetes service account used by both Reducto HTTP and worker deployments."
}

resource "google_service_account_iam_member" "workload_identity_user" {
  count = var.enable_workload_identity ? 1 : 0

  service_account_id = google_service_account.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[reducto/${var.workload_identity_service_account_name}]"
}

resource "kubectl_manifest" "workload_identity_annotation" {
  count = var.enable_workload_identity ? 1 : 0

  server_side_apply = true
  apply_only        = true
  field_manager     = "reducto-workload-identity"
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      namespace = "reducto"
      name      = var.workload_identity_service_account_name
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.service_account.email
      }
    }
  })

  depends_on = [helm_release.reducto, google_service_account_iam_member.workload_identity_user]
}
