variable "enabled" { type = bool }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_id" { type = string }
variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "tags" { type = map(string) }
