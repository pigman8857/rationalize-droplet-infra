# Auto-detect the laptop's public IP for firewall rules
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip = trimspace(data.http.my_ip.response_body)
}
