output "k3s_master_public_ip" {
  description = "Public IP address of the k3s master node"
  value       = module.ec2.master_public_ip
}

output "k3s_worker_public_ips" {
  description = "Public IP addresses of the k3s worker nodes"
  value       = module.ec2.worker_public_ips
}