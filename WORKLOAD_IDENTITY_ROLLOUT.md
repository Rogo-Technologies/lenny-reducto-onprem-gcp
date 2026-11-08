# Reducto Workload Identity rollout (LEV-1699)

This patch prepares a staged cutover. Both new flags default to false. It does not delete or recreate the service account key, HMAC key, Vision API key, cluster, or node pools.

Live GCP checks on November 8 confirmed Workload Identity is already enabled on both shared-services clusters. Every node pool uses GKE_METADATA. Both HTTP and worker deployments use the `reducto/reducto-reducto` Kubernetes service account. The `replicated` deployment uses a different account and is not included.

## Non-prod first

1. Pin the caller to this reviewed commit. Set `enable_workload_identity=true` and leave `use_workload_identity_credentials=false`.
2. Review the plan. It should add one service-account IAM member and one annotation manifest. It must not replace a node pool or rotate any credential. Lenny applies it.
3. Verify the IAM binding and `iam.gke.io/gcp-service-account` annotation on the existing Kubernetes service account. Wait for IAM propagation. The annotation is applied with server-side apply and `apply_only=true`, so Terraform must never delete the Helm-owned service account.
4. In a second reviewed apply, set `use_workload_identity_credentials=true`. This removes the injected JSON credential from Helm values. Verify in staging that both HTTP and worker processes use Application Default Credentials successfully.
5. Run a real document through staging. Check Vertex AI audit entries for `reducto-sa-standard` and verify the calls no longer include `serviceAccountKeyName`. Verify successful calls as well as the absence of key-backed calls. An empty log alone is not proof.
6. Hold prod unchanged until non-prod passes. Then repeat the same two applies and document test in prod.

The precondition rejects a credential switch while preparation is disabled. It cannot prove a previous apply happened. The two-stage operator sequence is mandatory.

## Key retirement

Keep `google_service_account_key.service_account_key` and its output unchanged during the cutover. After successful non-prod and prod evidence, use a separate reviewed Terraform removal to destroy the two keys. Removing the resource before the credential switch is proven would break running document processing.

Remove the non-prod project's key-creation exception only after its final Terraform-managed key is gone. Do not remove the prod exception just because Reducto moved: the prod project also has the drift-dashboard key.

## Vendor questions before the remaining credential removals

- Can the pinned chart write to Google Cloud Storage with the pod's Google identity instead of its S3-compatible HMAC key? If not, document an owner, rotation policy, and narrow `storage.restrictAuthTypes` exception. Do not turn on that org constraint yet.
- Can the Vision client use Application Default Credentials? If not, restrict the API key to Vision and the deployment's actual egress IPs after verifying them.
- Confirm that the deployed application version falls back to ADC when GOOGLE_APPLICATION_CREDENTIALS is absent. The staged non-prod check is required before prod rollout.

Rollback before key retirement is setting `use_workload_identity_credentials=false` in a reviewed apply. The original key remains available. Do not restore unrelated IAM policies or modify tenant bucket bindings.
