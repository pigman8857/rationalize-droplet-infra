output "droplet_ip" {
  description = "Droplet public IPv4 address"
  value       = digitalocean_droplet.main.ipv4_address
}

output "ssh_command" {
  description = "SSH into the Droplet"
  value       = "ssh -i generated/id_ed25519 root@${digitalocean_droplet.main.ipv4_address}"
}

output "mongodb_connection_string" {
  description = "MongoDB connection string"
  value       = "mongodb://${digitalocean_droplet.main.ipv4_address}:27017/?directConnection=true"
}

output "kafka_broker" {
  description = "Kafka broker address"
  value       = "${digitalocean_droplet.main.ipv4_address}:9092"
}

output "my_detected_ip" {
  description = "Your laptop's detected public IP"
  value       = local.my_ip
}
