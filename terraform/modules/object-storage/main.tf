resource "oci_objectstorage_bucket" "state" { compartment_id = var.compartment_ocid; name = var.bucket_name; namespace = data.oci_objectstorage_namespace.ns.namespace; versioning = "Enabled"; auto_tiering = "Disabled" }
data "oci_objectstorage_namespace" "ns" { compartment_id = var.compartment_ocid }
