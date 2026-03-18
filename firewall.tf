resource "digitalocean_firewall" "dev_database" {
  name        = "rationalization-dev-db-fw"
  droplet_ids = [digitalocean_droplet.main.id]

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["${local.my_ip}/32"]
  }

  # MongoDB
  inbound_rule {
    protocol         = "tcp"
    port_range       = "27017"
    source_addresses = ["${local.my_ip}/32"]
  }

  # Kafka Brokers
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9092"
    source_addresses = ["${local.my_ip}/32"]
  }

  # Kafka JMX
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9101"
    source_addresses = ["${local.my_ip}/32"]
  }

  # Allow all outbound (Docker pulls, apt updates, etc.)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
