# Shared token for cluster join authentication
locals {
  k3s_token = "super-secure-custom-k3s-token-12345"
}

resource "aws_security_group" "k3s_sg" {
  name        = "${var.environment}-sg"
  description = "Security group for k3s cluster nodes"
  vpc_id      = var.vpc_id

  # SSH Access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # k3s API Server
  ingress {
    description = "k3s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubelet metrics
  ingress {
    description = "Kubelet metrics"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # Flannel VXLAN overlay network
  ingress {
    description = "Flannel VXLAN overlay"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  # NodePort Services
  ingress {
    description = "NodePort Services range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Full outbound access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-sg"
  }
}

# 1 Master Node Instance
resource "aws_instance" "k3s_master" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # Changes hostname to master-k3s and installs k3s server
  user_data = <<-EOF
              #!/bin/bash
              # Change the system hostname
              hostnamectl set-hostname master-k3s
              echo "127.0.0.1 master-k3s" >> /etc/hosts
              
              # Install k3s with correct flags
              curl -sfL https://get.k3s.io | K3S_TOKEN="${local.k3s_token}" sh -s -
              EOF

  tags = {
    Name = "${var.environment}-master"
    Role = "master"
  }
}

# 2 Worker Node Instances
resource "aws_instance" "k3s_worker" {
  count                  = 2
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # Changes hostname to worker-k3s-1 / worker-k3s-2 and joins the cluster
  user_data = <<-EOF
              #!/bin/bash
              # Dynamically set hostname based on the count index
              WORKER_NAME="worker-k3s-${count.index + 1}"
              hostnamectl set-hostname $WORKER_NAME
              echo "127.0.0.1 $WORKER_NAME" >> /etc/hosts

              # Wait 30 seconds to guarantee master k3s API is fully up and listening
              sleep 30
              
              # Install k3s agent
              curl -sfL https://get.k3s.io | K3S_URL="https://${aws_instance.k3s_master.private_ip}:6443" K3S_TOKEN="${local.k3s_token}" sh -
              EOF

  tags = {
    Name = "${var.environment}-worker-${count.index + 1}"
    Role = "worker"
  }

  depends_on = [aws_instance.k3s_master]
}