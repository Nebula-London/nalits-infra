# Terraform

Reusable modules are driven by registry data. The tenancy stack is generic and receives one tenancy object plus an OCI provider alias. State is remote in a dedicated state tenancy/bucket. Never commit `.tfvars` containing credentials or state files.

Provider aliases are the mechanism for selecting different OCI credentials/tenancies. A new tenancy requires a provider credential/profile or delegated bootstrap authorization, not a new Terraform module.
