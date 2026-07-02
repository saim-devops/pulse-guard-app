#############################################
# EC2 Assume Role Policy
#############################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#############################################
# EC2 IAM Role
#############################################

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

#############################################
# Attach AWS Managed SSM Policy
#############################################

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#############################################
# Inline Policy
# Allow reading only this project's parameters
#############################################

data "aws_iam_policy_document" "ssm_parameters" {
  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParameterHistory"
    ]

    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/${var.environment}/*"
    ]
  }
}

resource "aws_iam_role_policy" "ssm_parameters" {
  name   = "${var.project_name}-${var.environment}-ssm-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ssm_parameters.json
}

#############################################
# EC2 Instance Profile
#############################################

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.environment}-instance-profile"
  role = aws_iam_role.ec2_role.name
}