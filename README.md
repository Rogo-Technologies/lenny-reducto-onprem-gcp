# Reducto

Deploy Reducto on Google Kubernetes Engine using Terraform

![Reducto on-prem Architecture for GCP](./reducto-architecture-on-gcp.png)


### Credentials 

Use one of the methods:

#### 1. Application Default Credentials

```
gcloud auth application-default login
```

#### 2. OAuth Access Token

For Terraform to use your [gcloud credentials](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference#access_token-1), run:

```
gcloud auth login
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)
```

### Billing Project

By default `var.project_id` is also billing project. This can be overriden by `var.billing_project_id`. Billing project is required for creating Cloud Vision API key.

See [Quota Management Configuration](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference#quota-management-configuration) in Terraform provider configuration.

### Quota

In your region, ensure there's sufficient quota for [Compute Optimized](https://cloud.google.com/compute/docs/compute-optimized-machines) instances (CPUs per region, CPU family per region), and Cloud Vision API https://console.cloud.google.com/iam-admin/quotas


### Security

A GKE cluster is provisioned with private nodes without public IP. Postgres instance is provisioned in private network without public IP.

GKE control plane is provisioned with both public and private IP - but access is limited to VPC and CIDR provided in `var.control_plane_allowed_cidrs`

### Terraform 

#### Terraform State

To use a bucket for Terraform state, create a bucket and update `backend.tf`.

OR you can skip this to quickly run Terraform plan and apply with locally managed `terraform.tfstate` state file for testing purposes.

#### Plan and Apply

At a minimum create a `terraform.tfvars` with following configuration:

```terraform
project_id                 = "your-gcp-project"
reducto_host               = "reducto.yourdomain.com"
reducto_helm_chart_version = "..."
reducto_helm_repo_username = "your-username"
reducto_helm_repo_password = "your-password"
```

And then:

```sh
terraform init
terraform plan
terraform apply
```

### DNS 

Ensure that domain name in `var.reducto_host` resolves to IP of internal load balancer of Reducto Ingress.

### Notes on Destroy

To delete, set `deletion_protection = false` and run `terraform destroy`. You may get following error, to resolve it manually delete from VPC under "VPC network peering" tab, and rerun `terraform destroy`.

<details>
<summary>
Service Networking Connection
</summary>

```
│ Error: Unable to remove Service Networking Connection, err: Error waiting for Delete Service Networking Connection: Error code 9, message: Failed to delete connection; Producer services (e.g. CloudSQL, Cloud Memstore, etc.) are still using this connection.
```
</details>
## Tenant releases (`modules/release`)

The root module deploys one shared Reducto release whose storage identity can
reach every bucket a request names. `modules/release` deploys an extra release
on the same cluster for one tenant: its own namespace, a Kubernetes service
account bound through Workload Identity to a Google service account the tenant
owns, the tenant bucket as the only `BUCKET`, its own database, optional API-key
authentication, and its own Gateway API internal load balancer for a Private
Service Connect attachment. No HMAC key is created.

```hcl
module "tenant_release" {
  source = "git::https://github.com/Rogo-Technologies/lenny-reducto-onprem-gcp.git//modules/release?ref=<sha>"
  providers = { helm = helm.reducto, kubectl = kubectl.reducto }

  project_id                 = var.cluster_project_id
  namespace                  = "reducto-acme"
  release_name               = "reducto-acme"
  gcp_service_account_email  = "reducto-tenant@acme-project.iam.gserviceaccount.com"
  gcp_project_id             = "acme-project"
  bucket_name                = "reducto-acme-us-central1-prod"
  database_url               = "postgresql://..."   # a database on module.pg (outputs db_instance_name / db_private_ip)
  api_key                    = random_password.acme.result
  reducto_helm_chart_version = "1.12.20-1"
  reducto_helm_repo_username = var.reducto_helm_repo_username
  reducto_helm_repo_password = var.reducto_helm_repo_password
}
```

Grant `roles/iam.workloadIdentityUser` on the Google service account to
`module.tenant_release.workload_identity_member`, and `roles/storage.objectAdmin`
on the tenant bucket to the Google service account. The root module's
`reducto-sa` must no longer hold a role on that bucket.
