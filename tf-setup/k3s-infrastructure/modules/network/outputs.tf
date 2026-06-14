output "vpc_id" {
  value = aws_vpc.k3s_vpc.id
}

output "public_subnet_id" {
  value = aws_subnet.k3s_public_subnet.id
}