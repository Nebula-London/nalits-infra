# Always Free boundary

Always Free is a capacity constraint, not an architecture guarantee. The platform therefore validates shape availability, quotas, storage and regional capacity before deployment. Keep state in Object Storage rather than a compute VM; group low-risk Compose services where blast radius permits; use dedicated VMs for security boundaries and high-risk services.

If Always Free capacity is insufficient, the migration path is: preserve the registry and module interfaces, move selected workloads to paid compute/storage, then add HA only where RPO/RTO requires it. Never silently assume paid resources.
