# Trust boundaries

**Internet -> Cloudflare:** TLS, DNS, WAF/proxy policy as appropriate.

**Cloudflare -> public OCI:** only public edge ports; origin is not a private environment.

**Public -> private:** explicit service-to-service authorization only; never a broad route to DEV/PROD.

**Engineer -> private:** WireGuard plus SSO/group authorization; no public SSH.

**DEV <-> PROD:** denied by default at routing/NSG/IAM layers.

**Runtime -> OCI services:** instance principal/dynamic group and least-privilege policy.

**State:** separate tenancy/bucket with versioning and restricted automation identity.
