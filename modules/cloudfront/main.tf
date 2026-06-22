# Fronts the frontend's ALB with CloudFront. Gated by var.enabled in root
# main.tf — the ALB doesn't exist until ArgoCD syncs the Ingress, so this is
# always a second, later apply once you have a real ALB DNS name, never the
# same apply that creates the cluster.

resource "aws_cloudfront_distribution" "frontend" {
  count   = var.enabled ? 1 : 0
  enabled = true
  comment = "procurement-${var.environment}-frontend"
  aliases = [var.domain_name]

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port  = 80
      https_port = 443
      # http-only to the origin: CloudFront validates an HTTPS origin's cert
      # against the ORIGIN hostname (the NLB's *.elb.amazonaws.com name), but
      # our ACM cert is for *.procure-flow.online — that mismatch fails an
      # https-only origin. So TLS terminates at the edge (viewer ->
      # CloudFront via the ACM cert) and CloudFront reaches the NLB over HTTP
      # on port 80 within AWS. viewer_protocol_policy still forces HTTPS for
      # end users.
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    # Dynamic SPA + API behind this origin — no edge caching of responses by
    # default. The app's own Cache-Control headers govern actual caching of
    # static assets; this just gives CDN/TLS termination at the edge.
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = var.tags
}

resource "aws_route53_record" "frontend_alias" {
  count   = var.enabled ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend[0].domain_name
    zone_id                = aws_cloudfront_distribution.frontend[0].hosted_zone_id
    evaluate_target_health = false
  }
}
