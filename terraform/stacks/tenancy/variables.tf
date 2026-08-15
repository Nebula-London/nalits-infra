variable "tenancy" { type = any }
variable "compartment_ocid" { type = string }
variable "ssh_public_key" { type = string; sensitive = true }
