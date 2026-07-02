#############################################
# Ubuntu 22.04 LTS AMI
#############################################

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#############################################
# Kubernetes Master Node
#############################################

resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "${var.project_name}-${var.environment}-master"
    Role = "master"
  }
}

#############################################
# Kubernetes Worker Nodes
#############################################

resource "aws_instance" "worker" {
  for_each = var.worker_nodes

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = each.key
    Role = "worker"
  }
}