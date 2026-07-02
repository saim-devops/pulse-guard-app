variable "aws_region" {
  default = "ap-south-1"
  type    = string
}

variable "project_name" {
  default = "pulseguard-app"
  type    = string
}

variable "environment" {
  default = "Dev"
  type    = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
  type = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  default = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]
  type = list(string)
}

variable "my_ip" {
  description = "Your local machine's public IP address in CIDR notation — value comes from terraform.tfvars"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ssh-key" {
  description = "Existing EC2 key pair name — value comes from terraform.tfvars"
  type        = string
}

variable "worker_nodes" {
  description = "Map of Kubernetes worker nodes. subnet_index picks which public subnet (AZ) each worker lands in."
  type = map(object({
    subnet_index = number
  }))

  default = {
    "worker-1" = { subnet_index = 0 }
    "worker-2" = { subnet_index = 1 }
    "worker-3" = { subnet_index = 0 }
  }
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "postgres"
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "domain_name" {
  description = "Root domain already hosted in Route53"
  type        = string
  default     = "saimm.online"
}

variable "subdomain" {
  description = "Subdomain the app is served on"
  type        = string
  default     = "status"
}