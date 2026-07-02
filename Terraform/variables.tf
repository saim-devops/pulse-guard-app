variable "aws_region" {
    default = "ap-south-1"
    type = string
}

variable "project_name" {
    default = "pulseguard-app"
    type = string
}

variable "environment" {
    default = "Dev"
    type = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default = "10.0.0.0/16"
  type        = string

}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  default = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]
  type        = list(string)
}

variable "my_ip" {
  description = "Your public IP address in CIDR notation"
  type        = string
    # write my_ip here
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string

  default = "t3.micro"
}

variable "worker_nodes" {
  description = "Map of Kubernetes worker nodes"

  type = map(object({}))

  default = {
    "worker-1" = {}
    "worker-2" = {}
    "worker-3" = {}
  }
}

variable "db_name" {
  description = "Database name"
  type        = string

  default = "appdb"
}

variable "db_username" {
  description = "Database username"
  type        = string

  default = "postgres"
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string

  default = "db.t3.micro"
}