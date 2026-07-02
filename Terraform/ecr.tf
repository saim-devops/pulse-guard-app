#############################################
# Web Application Repository
#############################################

resource "aws_ecr_repository" "web" {
  name = "${var.project_name}-${var.environment}-web"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"
}

#############################################
# Checker Application Repository
#############################################

resource "aws_ecr_repository" "checker" {
  name = "${var.project_name}-${var.environment}-checker"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"
}

#############################################
# Lifecycle Policy - Web
#############################################

resource "aws_ecr_lifecycle_policy" "web" {
  repository = aws_ecr_repository.web.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 10 images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}

#############################################
# Lifecycle Policy - Checker
#############################################

resource "aws_ecr_lifecycle_policy" "checker" {
  repository = aws_ecr_repository.checker.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 10 images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}