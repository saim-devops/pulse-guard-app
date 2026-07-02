#############################################
# Generate Database Password
#############################################

resource "random_password" "db_password" {
  length  = 20
  special = true
}

#############################################
# RDS Subnet Group
#############################################

resource "aws_db_subnet_group" "main" {
  name = "${var.project_name}-${var.environment}-db-subnet-group"

  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

#############################################
# PostgreSQL RDS Instance
#############################################

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  engine         = "postgres"
  engine_version = "16"

  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres"
  }
}