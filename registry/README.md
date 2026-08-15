# Tenancy registry

`tenancies.yaml` is the declarative source of truth. A tenancy declares its profile, environment, CIDR pool, capabilities, access groups and VM roles. Terraform consumes this data; it must not contain duplicated `dev.tf`, `prod.tf`, or customer-specific modules.

A new tenancy is onboarded by adding data and completing the one-time authorization ceremony for that independent OCI tenancy. The allocator validates CIDR overlap before Terraform runs.
