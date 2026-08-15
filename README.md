# nalits-infra

Production-oriented OCI zero-trust platform for independent OCI tenancies. The platform is registry-driven and capability-based: the same Terraform modules, bootstrap scripts, and Compose patterns can provision security, public, development, production, observability, state, AI, DR, and future tenancies without creating tenancy-specific modules.

## Principles

- Independent OCI tenancies are the isolation boundary.
- Default deny: private environments have no public IPs and no implicit cross-environment routing.
- Human access: SSO/group authorization -> WireGuard -> private resource -> short-lived SSH certificate where practical.
- Runtime access: OCI dynamic groups/instance principals and least privilege.
- Secrets: OCI Vault; no credentials in Git.
- Public edge: Cloudflare -> explicitly exposed OCI edge -> explicitly authorized services.
- Terraform is authoritative for infrastructure; Docker Compose deploys services; Bash is idempotent orchestration.
- Kubernetes is intentionally excluded from v1.

## Layout

```text
registry/                 tenancy and platform source of truth
terraform/modules/        reusable OCI modules
terraform/stacks/         generic tenancy/state/global stacks
compose/                  reusable service deployment patterns
scripts/                  validation, onboarding and bootstrap tooling
docs/                     architecture, security, operations and recovery
.github/workflows/        CI validation
```

## Quick start

```bash
cp examples/tenancies.example.yaml registry/tenancies.yaml
cp examples/platform.example.yaml registry/platform.yaml
python3 scripts/validate-registry.py validate --file registry/tenancies.yaml --platform registry/platform.yaml
./scripts/platformctl.sh tenancy onboard --name ai-prod --purpose ai --environment prod
```

Never put real OCIDs, tokens, private keys or passwords in examples. The example registry intentionally uses placeholders.

## Automation boundary

Fully automatable: registry validation, CIDR allocation, Terraform plans/applies after credentials are authorized, VM bootstrap, Docker/Compose installation, monitoring/backup configuration, inventory generation, health checks and recovery workflows.

Human approval: authorizing a new independent tenancy, granting human production/security groups, Cloudflare account changes, break-glass use, and production deployment approval.

Not realistically automatic without an external trust anchor: granting a brand-new tenancy access to the control plane and recovery from a simultaneously lost identity/backup/state authority. Those remain explicit bootstrap/security ceremonies.

## Always Free

The design prefers OCI Always Free resources but does not assume unlimited capacity. Compute shape availability, Ampere capacity, boot/block volume limits, Autonomous Database limits, Vault quotas and regional capacity must be checked at deployment time. See `docs/architecture/always-free.md` for the sizing boundary and low-cost migration path.
