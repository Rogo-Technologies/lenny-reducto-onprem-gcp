output "bucket_name" {
  description = "The name of the private GCS bucket"
  value       = google_storage_bucket.private_bucket.name
}

output "bucket_url" {
  description = "The URL of the private GCS bucket"
  value       = google_storage_bucket.private_bucket.url
}

output "google_access_key_id" {
  description = "The access key ID for S3 compatible access to the bucket"
  value       = google_storage_hmac_key.s3_compatible_key.access_id
  sensitive   = true
}

output "google_secret_access_key" {
  description = "The secret access key for S3 compatible access to the bucket"
  value       = google_storage_hmac_key.s3_compatible_key.secret
  sensitive   = true
}

output "google_service_account_email" {
  description = "The GCP Service Account created for reducto"
  value       = google_service_account.service_account.email
}

output "database_url" {
  description = "The URL of the database"
  value       = local.database_url
  sensitive   = true
}

output "service_account_key" {
  description = "The key for the Reducto service account"
  value       = local.service_account_key
  sensitive   = true
}

output "vpc_network_name" {
  description = "The name of the VPC network created for Reducto"
  value       = module.network.network_name
}

output "db_instance_name" {
  description = "Cloud SQL instance name; tenant releases (modules/release) create their own database on it"
  value       = module.pg.instance_name
}

output "db_private_ip" {
  description = "Private IP of the Cloud SQL instance, for tenant release DATABASE_URLs"
  value       = module.pg.private_ip_address
}

output "cluster_name" {
  description = "GKE cluster name, for callers that configure their own helm/kubectl providers for modules/release"
  value       = var.cluster_name
}
