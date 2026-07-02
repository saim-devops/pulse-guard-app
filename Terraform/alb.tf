#############################################
# Internet-facing ALB
#############################################

resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

#############################################
# Target group — points at ingress-nginx's NodePort.
# Update the port here if you configure ingress-nginx on a different NodePort.
#############################################

resource "aws_lb_target_group" "http" {
  name     = "${var.project_name}-${var.environment}-tg-http"
  port     = 30080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }
}

#############################################
# Only workers — the master is tainted NoSchedule so ingress pods
# never land there, no point registering it as a target
#############################################

resource "aws_lb_target_group_attachment" "workers" {
  for_each = aws_instance.worker

  target_group_arn = aws_lb_target_group.http.arn
  target_id        = each.value.id
  port              = 30080
}

#############################################
# HTTP only — CloudFront terminates TLS at the edge and talks to
# this ALB over HTTP within the AWS network (see cloudfront.tf)
#############################################

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}
