mock_provider "google" {
  mock_resource "google_service_account_key" {
    defaults = { private_key = "e30=" }
  }
  mock_resource "google_service_account" {
    defaults = {
      member = "serviceAccount:reducto-sa-standard@shared-services-non-prod-d3c2.iam.gserviceaccount.com"
      email  = "reducto-sa-standard@shared-services-non-prod-d3c2.iam.gserviceaccount.com"
      name   = "projects/shared-services-non-prod-d3c2/serviceAccounts/reducto-sa-standard@shared-services-non-prod-d3c2.iam.gserviceaccount.com"
    }
  }
}
mock_provider "google-beta" {}
mock_provider "helm" {}
mock_provider "kubectl" {}
mock_provider "random" {}

variables {
  project_id                   = "shared-services-non-prod-d3c2"
  region                       = "us-central1"
  reducto_helm_repo_username   = "test"
  reducto_helm_repo_password   = "test"
  reducto_host                 = ""
  reducto_service_account_name = "reducto-sa-standard"
}

override_module {
  target = module.network
  outputs = {
    network_name      = "reducto-standard"
    network_self_link = "projects/shared-services-non-prod-d3c2/global/networks/reducto-standard"
  }
}
override_module { target = module.cloud-nat }
override_module { target = module.private_service_access }
override_module {
  target  = module.pg
  outputs = { private_ip_address = "10.0.0.1" }
}

run "existing_credentials_unchanged_by_default" {
  command = plan
  module { source = "./tests/fixtures/without-gke" }
  plan_options {
    target = [google_service_account_iam_member.workload_identity_user, kubectl_manifest.workload_identity_annotation, helm_release.reducto]
  }
  assert {
    condition     = length(google_service_account_iam_member.workload_identity_user) == 0 && length(kubectl_manifest.workload_identity_annotation) == 0
    error_message = "Default settings must not change a running deployment's identity."
  }
  assert {
    condition     = contains(nonsensitive(keys(local.reducto_sensitive_env)), "GOOGLE_APPLICATION_CREDENTIALS")
    error_message = "The default must keep injecting the existing key."
  }
}

run "prepare_without_switching_credentials" {
  command = plan
  module { source = "./tests/fixtures/without-gke" }
  plan_options {
    target = [google_service_account_iam_member.workload_identity_user, kubectl_manifest.workload_identity_annotation, helm_release.reducto]
  }
  variables { enable_workload_identity = true }
  assert {
    condition     = google_service_account_iam_member.workload_identity_user[0].member == "serviceAccount:shared-services-non-prod-d3c2.svc.id.goog[reducto/reducto-reducto]"
    error_message = "Only the verified Reducto Kubernetes service account may use the Google identity."
  }
  assert {
    condition     = kubectl_manifest.workload_identity_annotation[0].apply_only && kubectl_manifest.workload_identity_annotation[0].server_side_apply
    error_message = "The annotation must not take ownership of deleting Helm's Kubernetes service account."
  }
  assert {
    condition     = contains(nonsensitive(keys(local.reducto_sensitive_env)), "GOOGLE_APPLICATION_CREDENTIALS")
    error_message = "Preparation must keep the working credential path."
  }
  assert {
    condition     = length(local.workload_identity_values) == 0
    error_message = "Preparation must not add Workload Identity settings to Reducto's Helm values."
  }
}

run "switch_only_when_explicitly_requested" {
  command = plan
  module { source = "./tests/fixtures/without-gke" }
  plan_options {
    target = [google_service_account_iam_member.workload_identity_user, kubectl_manifest.workload_identity_annotation, helm_release.reducto]
  }
  variables {
    enable_workload_identity          = true
    use_workload_identity_credentials = true
  }
  assert {
    condition     = !contains(nonsensitive(keys(local.reducto_sensitive_env)), "GOOGLE_APPLICATION_CREDENTIALS")
    error_message = "The opt-in switch must remove the injected JSON credential."
  }
  assert {
    condition     = contains(nonsensitive(keys(local.reducto_sensitive_env)), "GCP_SECRET_ACCESS_KEY") && contains(nonsensitive(keys(local.reducto_sensitive_env)), "GCP_API_KEY")
    error_message = "The vendor's HMAC and Vision credentials are separate and must remain unchanged."
  }
  assert {
    condition     = contains(helm_release.reducto.values, yamlencode({ env = { GCP_SERVICE_ACCOUNT_EMAIL = "reducto-sa-standard@shared-services-non-prod-d3c2.iam.gserviceaccount.com" } }))
    error_message = "Without the key, Reducto needs GCP_SERVICE_ACCOUNT_EMAIL to detect Google credentials, or OCR falls back to AWS Textract."
  }
}

run "reject_switch_without_preparation" {
  command = plan
  module { source = "./tests/fixtures/without-gke" }
  plan_options {
    target = [google_service_account_iam_member.workload_identity_user, kubectl_manifest.workload_identity_annotation, helm_release.reducto]
  }
  variables { use_workload_identity_credentials = true }
  expect_failures = [helm_release.reducto]
}
