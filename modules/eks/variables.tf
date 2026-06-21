variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnets" { type = list(string) }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "node_desired_size" { type = number }
variable "node_instance_types" { type = list(string) }
variable "tags" { type = map(string) }

variable "use_ubuntu_ami" {
  description = "Use Canonical's Ubuntu EKS-optimized AMI instead of the default Amazon Linux. Defaults off — verify the SSM parameter resolves before turning this on (see comment in main.tf)."
  type        = bool
  default     = false
}
variable "ubuntu_ami_ssm_path" {
  description = "SSM parameter path for the Ubuntu EKS AMI. Only used when use_ubuntu_ami = true."
  type        = string
  default     = "/aws/service/canonical/ubuntu/eks/22.04/1.30/stable/current/amd64/hvm/ebs-gp2/ami-id"
}
