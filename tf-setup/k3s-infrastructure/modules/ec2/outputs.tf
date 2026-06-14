output "master_public_ip" {
  value = aws_instance.k3s_master.public_ip
}

output "worker_public_ips" {
  value = aws_instance.k3s_worker[*].public_ip
}