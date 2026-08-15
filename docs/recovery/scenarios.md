# Recovery scenarios

**VM destroyed:** Terraform recreates the VM; bootstrap installs the baseline; Compose restores services; restic restores persistent data; health checks validate.

**DEV/PROD destroyed:** rebuild the tenancy VCN/compute from registry and restore application data. No cross-environment trust is required.

**SSO unavailable:** use controlled break-glass only; restore identity service from backup and rotate emergency credentials afterward.

**WireGuard unavailable:** restore the security tenancy VPN host/config from backup; private workloads remain unexposed.

**State deleted:** restore Object Storage version or backup; never reconstruct state by hand if a known good version exists.

**Entire tenancy lost:** authorize replacement tenancy, allocate a new non-overlapping CIDR, apply the generic stack, bootstrap, restore data and validate isolation.

**Forgejo lost:** rebuild from Terraform/Compose and restore repository/application data from restic/GitHub backup.

**Backup server unavailable:** OCI workloads continue; repair/replace backup target and run an integrity/retention audit before declaring protection restored.
