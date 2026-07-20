module "network" {
  source = "./modules/network"

  project_name = var.project_name
}

module "security_group" {
  source = "./modules/security-group"

  vpc_id          = module.network.vpc_id
  trusted_ip_cidr = var.trusted_ip_cidr
  project_name    = var.project_name
}
