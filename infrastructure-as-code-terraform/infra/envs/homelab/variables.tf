variable "pizza_domain" {
  type    = string
  default = "pizza"
}

variable "vm_host_ip" {
  type    = string
  default = "192.168.2.71"
}

variable "postgres_user" {
  type    = string
  default = "pizza"
}

variable "postgres_db" {
  type    = string
  default = "toppings"
}

variable "caddy_http_port" {
  type    = number
  default = 80
}

variable "caddy_https_port" {
  type    = number
  default = 443
}
