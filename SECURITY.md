# Security policy

Report security issues privately to the repository owner. Never open an issue containing credentials or exploitable details.

## Non-negotiables

- No secrets in Git or examples.
- No public SSH on private environments.
- No public IPs on DEV/PROD/SECURITY workloads unless an explicit architecture exception is documented.
- No default DEV<->PROD routing.
- Terraform automation uses dedicated least-privilege identities.
- Break-glass credentials are offline and audited.
