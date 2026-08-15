output "vcn_id" { value = module.network.vcn_id }
output "private_subnet_id" { value = module.network.private_subnet_id }
output "instances" { value = module.compute.instances }
