data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "bastion" {
  count       = var.enabled ? 1 : 0
  name        = "procurement-${var.environment}-bastion"
  description = "Bastion host - SSM Session Manager only, zero inbound rules, no SSH"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to SSM/EKS/ECR endpoints and package mirrors"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_iam_role" "bastion" {
  count = var.enabled ? 1 : 0
  name  = "procurement-${var.environment}-bastion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "eks_describe" {
  count = var.enabled ? 1 : 0
  name  = "eks-describe"
  role  = aws_iam_role.bastion[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "eks:ListClusters"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:aws:eks:${var.aws_region}:*:cluster/${var.cluster_name}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  count = var.enabled ? 1 : 0
  name  = "procurement-${var.environment}-bastion"
  role  = aws_iam_role.bastion[0].name
}

resource "aws_instance" "bastion" {
  count                  = var.enabled ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.bastion[0].id]
  iam_instance_profile   = aws_iam_instance_profile.bastion[0].name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_size = 10
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf install -y unzip
    curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get_helm.sh
    chmod +x /tmp/get_helm.sh
    /tmp/get_helm.sh
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
    cat > /etc/profile.d/eks-kubeconfig.sh <<'PROFILE'
    aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name} >/dev/null 2>&1 || true
    PROFILE
    chmod +x /etc/profile.d/eks-kubeconfig.sh
  EOF

  tags = merge(var.tags, { Name = "procurement-${var.environment}-bastion" })
}
