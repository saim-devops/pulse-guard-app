#############################################
# Existing hosted zone for saimm.online
#############################################

data "aws_route53_zone" "root" {
  name         = "${var.domain_name}."
  private_zone = false
}

#############################################
# ACM cert — must be us-east-1 for CloudFront, hence the aws.use1 alias
#############################################

resource "aws_acm_certificate" "cdn" {
  provider          = aws.use1
  domain_name       = "${var.subdomain}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

#############################################
# DNS validation records — one per domain_validation_options entry
#############################################

resource "aws_route53_record" "cdn_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cdn.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.root.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cdn" {
  provider                = aws.use1
  certificate_arn         = aws_acm_certificate.cdn.arn
  validation_record_fqdns = [for r in aws_route53_record.cdn_validation : r.fqdn]
}
