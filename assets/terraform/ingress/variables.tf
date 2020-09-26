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

variable "application_port" {
  description = "The port that you want to expose to the external load balancer"
  default     = 8080
}

variable "custom_data_file" {
  default = "./templates/nginx-ingress.sh"
}
variable "tags" {
  description = "A map of the tags to use for the resources that are deployed"
  type        = "map"

  default = {
    environment = "demo"
  }
}
