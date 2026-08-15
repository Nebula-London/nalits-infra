# RPO/RTO baseline

Initial target: daily full-consistency application backups plus frequent incremental restic snapshots where workload size permits; Terraform state uses Object Storage versioning. Recovery time is dominated by OCI capacity and data restore rather than infrastructure authoring because the platform is declarative.

Set service-specific RPO/RTO before production launch. Always Free is not an HA guarantee; critical services may require paid resources or a second recovery tenancy.
