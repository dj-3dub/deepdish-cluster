output "pizza_endpoints" {
  value = {
    oven   = "http://oven.${var.pizza_domain}"
    api    = "http://api.${var.pizza_domain}"
    status = "http://status.${var.pizza_domain}"
  }
}
