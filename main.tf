# ─── SSH Key ────────────────────────────────────────────────

resource "tls_private_key" "droplet" {
  algorithm = "ED25519"
}

resource "digitalocean_ssh_key" "droplet" {
  name       = local.droplet_name
  public_key = tls_private_key.droplet.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.droplet.private_key_openssh
  filename        = "${path.module}/generated/id_ed25519"
  file_permission = "0600"
}

# ─── Droplet ───────────────────────────────────────────────

resource "digitalocean_droplet" "main" {
  name     = local.droplet_name
  region   = var.region
  size     = var.droplet_size
  image    = var.droplet_image
  ssh_keys = [digitalocean_ssh_key.droplet.fingerprint]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.droplet.private_key_openssh
    host        = self.ipv4_address
  }

  # Upload the templated docker-compose file
  provisioner "file" {
    content = templatefile("${path.module}/templates/cloud-docker-compose.yml.tpl", {
      droplet_ip   = self.ipv4_address
      project_name = var.project_name
    })
    destination = "/root/docker-compose.yml"
  }

  # Install Docker and start services
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "curl -fsSL https://get.docker.com | sh",
      "systemctl enable --now docker",
      "cd /root && docker compose up -d",
    ]
  }
}

# ─── Kafka Topics ──────────────────────────────────────────

resource "terraform_data" "kafka_topics" {
  depends_on = [digitalocean_droplet.main]

  triggers_replace = [var.kafka_topics, digitalocean_droplet.main.id]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.droplet.private_key_openssh
    host        = digitalocean_droplet.main.ipv4_address
  }

  provisioner "remote-exec" {
    inline = concat(
      # Wait for Kafka broker to be ready (up to 60s)
      [
        "for i in $(seq 1 12); do docker exec ${var.project_name}-kafka-cloud kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1 && break || sleep 5; done",
      ],
      # Create each topic
      [for t in var.kafka_topics :
        "docker exec ${var.project_name}-kafka-cloud kafka-topics --create --topic ${t.name} --partitions ${t.partitions} --replication-factor ${t.replication_factor} --bootstrap-server localhost:9092 --if-not-exists"
      ]
    )
  }
}

# ─── Generate local docker-compose ─────────────────────────

resource "local_file" "local_compose" {
  content = templatefile("${path.module}/templates/local-docker-compose.yml.tpl", {
    droplet_ip   = digitalocean_droplet.main.ipv4_address
    project_name = var.project_name
  })
  filename = "${path.module}/generated/local-docker-compose.yml"
}
