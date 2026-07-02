#############################################
# Secrets generated once, never committed to git
#############################################

resource "random_password" "auth_secret" {
  length  = 32
  special = false
}

resource "random_password" "admin_password" {
  length  = 20
  special = true
}

locals {
  ssm_prefix   = "/${var.project_name}/${var.environment}"
  database_url = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.postgres.address}:5432/${var.db_name}"
}

#############################################
# App config/secrets — SecureString for anything sensitive
#############################################

resource "aws_ssm_parameter" "database_url" {
  name  = "${local.ssm_prefix}/DATABASE_URL"
  type  = "SecureString"
  value = local.database_url
}

resource "aws_ssm_parameter" "auth_secret" {
  name  = "${local.ssm_prefix}/AUTH_SECRET"
  type  = "SecureString"
  value = random_password.auth_secret.result
}

resource "aws_ssm_parameter" "admin_email" {
  name  = "${local.ssm_prefix}/ADMIN_EMAIL"
  type  = "String"
  value = "admin@${var.domain_name}"
}

resource "aws_ssm_parameter" "admin_password" {
  name  = "${local.ssm_prefix}/ADMIN_PASSWORD"
  type  = "SecureString"
  value = random_password.admin_password.result
}

#############################################
# Non-secret config CI/CD reads to know where to push images
#############################################

resource "aws_ssm_parameter" "ecr_repo_web" {
  name  = "${local.ssm_prefix}/ECR_REPO_WEB"
  type  = "String"
  value = aws_ecr_repository.web.repository_url
}

resource "aws_ssm_parameter" "ecr_repo_checker" {
  name  = "${local.ssm_prefix}/ECR_REPO_CHECKER"
  type  = "String"
  value = aws_ecr_repository.checker.repository_url
}
