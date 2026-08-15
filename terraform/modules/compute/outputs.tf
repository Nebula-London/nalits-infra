output "instances" { value = { for k,v in oci_core_instance.this : k => { id=v.id; private_ip=v.private_ip } } }
