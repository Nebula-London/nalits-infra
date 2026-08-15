# Threat model

| Threat | Primary controls | Recovery |
|---|---|---|
| stolen developer credential | SSO MFA, groups, short-lived SSH certs, VPN | revoke identity/certs |
| compromised laptop | no public private SSH, VPN keys revocable, least privilege | revoke peer, rotate credentials |
| compromised public app | isolated edge, explicit egress, no DEV/PROD default route | rebuild from Terraform/backup |
| compromised DEV | separate tenancy/network/IAM | destroy/rebuild DEV |
| SSO compromise | separate security boundary, audit, break-glass | disable federation, use offline emergency path |
| Terraform credential compromise | dedicated least privilege, Vault, short-lived/bootstrap credentials | revoke and rotate |
| exposed database | private endpoint, NSGs, identity | rotate secrets, restore if needed |
| stolen backup | restic encryption, offline/offsite keys | rotate backup credentials |
| malicious insider | group-based authorization, approvals, audit | revoke access and investigate |
| Cloudflare/DNS compromise | MFA, scoped API tokens, origin restrictions | restore DNS and rotate tokens |
