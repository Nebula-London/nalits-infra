variable "compartment_ocid" { type = string }
variable "subnet_id" { type = string }
variable "ssh_public_key" { type = string; sensitive = true }
variable "vms" { type = list(any); default = [] }
