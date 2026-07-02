output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "worker_public_ips" {
  value = { for k, v in aws_instance.worker : k => v.public_ip }
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "public_url" {
  value = "https://${var.subdomain}.${var.domain_name}"
}

output "ecr_web_repo" {
  value = aws_ecr_repository.web.repository_url
}

output "ecr_checker_repo" {
  value = aws_ecr_repository.checker.repository_url
}

output "ssm_prefix" {
  value = local.ssm_prefix
}

output "route53_name_servers" {
  value = aws_route53_zone.root.name_servers
}
