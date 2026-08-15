provider "oci" { alias = "target"; tenancy_ocid = var.tenancy.tenancy_id; region = var.tenancy.region }
