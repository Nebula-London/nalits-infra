# Network architecture

```text
Internet -> Cloudflare -> public edge -> explicit service boundary
Engineer -> WireGuard -> private networks -> authorized resource
DEV -X- PROD; PROD -X- DEV; private subnets have no public IPs
```

Cloudflare is the public DNS/proxy/TLS edge, not a substitute for OCI NSGs, route tables, identity or service authorization. Public services must call only explicitly allowed private endpoints. Cross-environment routes are absent by default. Database endpoints are private-only and reachable only from authorized application subnets/identities.
