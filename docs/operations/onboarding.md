# New tenancy onboarding

1. Create/identify the new independent OCI tenancy.
2. Perform one-time authorization using a tightly scoped bootstrap identity; do not give the control plane unrestricted root access.
3. Add one registry record and capabilities.
4. Validate region, quotas and CIDR availability.
5. Apply the generic tenancy stack with the provider alias for that tenancy.
6. Bootstrap Ubuntu 24.04, Docker and Compose idempotently.
7. Deploy capability-selected services.
8. Establish WireGuard routes and identity groups.
9. Configure monitoring and restic backup.
10. Generate inventory and run isolation/health tests.

Example: `ai-prod` is just another registry record; no new Terraform module is written.
