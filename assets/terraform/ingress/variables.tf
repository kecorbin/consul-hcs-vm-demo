variable "endpoint" {}
variable "consulconfig" {}
variable "ca_cert" {}
variable "ssh_public_key" {
  description = "SSH key for the consul instances"
}
variable "consul_token" {}
variable "ingress_count" {
  default = 2
}
