module "network" {
  source             = "./modules/network"
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

module "ec2" {
  source            = "./modules/ec2"
  environment       = var.environment
  vpc_id            = module.network.vpc_id
  public_subnet_id  = module.network.public_subnet_id
  instance_type     = var.instance_type
  ami_id            = var.ami_id
  ssh_key_name      = var.ssh_key_name
}