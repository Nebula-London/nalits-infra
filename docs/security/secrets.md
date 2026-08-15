# Secrets

OCI Vault is the default store for application credentials, database credentials, VPN material, SSO bootstrap values and CI/CD secrets. Runtime instances use dynamic groups/instance principals to retrieve only the secrets they need. Secrets are never committed to Git or placed directly in Compose files.

Terraform state can contain sensitive provider-managed values; therefore state is encrypted, versioned, isolated in the state tenancy, backed up and accessible only to the Terraform automation identity.
