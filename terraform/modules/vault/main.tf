resource "oci_kms_vault" "this" { compartment_id = var.compartment_ocid; display_name = var.name; vault_type = "DEFAULT" }
