output "namespace" {
  value = var.namespace
}

output "release_name" {
  value = var.release_name
}

output "kubernetes_service_account_name" {
  description = "ServiceAccount the chart runs as; annotated with the Google service account."
  value       = local.kubernetes_service_account_name
}

output "workload_identity_member" {
  description = "IAM member to grant roles/iam.workloadIdentityUser on the Google service account."
  value       = local.workload_identity_member
}

output "http_service_name" {
  value = local.http_service_name
}

output "gateway_name" {
  description = "Gateway API resource name when enable_global_access is true; the GKE forwarding rule it creates carries this name."
  value       = var.enable_global_access ? "${var.release_name}-gateway" : null
}

output "auth_enabled" {
  value = local.auth_enabled
}
