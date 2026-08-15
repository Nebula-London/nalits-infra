# Tenancy model

The platform starts with security, public, development, production, observability and Terraform-state roles but treats these as data, not fixed Terraform stacks. A future `ai-prod` tenancy is a new registry record with `profile: environment`, `environment: prod`, and capabilities such as `docker_host`, `rag`, `monitoring_agent`, and `backup_agent`.

Onboarding sequence: authorize tenancy -> validate OCI access/quota/region -> allocate non-overlapping CIDR -> apply IAM baseline -> VCN/subnets/NSGs/routes -> compute -> bootstrap -> Compose capabilities -> monitoring/backup -> inventory -> isolation tests.

No platform redesign or new Terraform module is required for a new role that fits existing capabilities.
