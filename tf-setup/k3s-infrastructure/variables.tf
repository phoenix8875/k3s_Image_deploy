variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for k3s nodes"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "The AMI ID to use for the EC2 instances (Ubuntu 22.04 / 24.04 recommended)"
  type        = string
}

variable "ssh_key_name" {
  description = "The name of the existing AWS EC2 Key Pair to use for SSH access"
  type        = string
}