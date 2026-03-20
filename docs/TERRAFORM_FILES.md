# Terraform Files Explanation

Detailed explanation of every Terraform file and setting in this project.

---

## versions.tf — Providers & Versions

```hcl
terraform {
  required_version = ">= 1.5"
}
```

You need Terraform CLI 1.5 or newer installed on your machine.

### Providers

| Provider | Version | Purpose |
|----------|---------|---------|
| `digitalocean/digitalocean` | `~> 2.36` | Talks to the DigitalOcean API to create Droplets, firewalls, SSH keys |
| `hashicorp/local` | `~> 2.5` | Writes files to your laptop (generated compose file and SSH key) |
| `hashicorp/tls` | `~> 4.0` | Generates the SSH key pair entirely inside Terraform (no manual `ssh-keygen`) |
| `hashicorp/http` | `~> 3.4` | Makes HTTP requests — used to auto-detect your laptop's public IP |

```hcl
provider "digitalocean" {
  token = var.do_token
}
```

Authenticates with DigitalOcean using your API token.

---

## variables.tf — Input Variables

| Variable | Type | Default | Required | Purpose |
|----------|------|---------|----------|---------|
| `do_token` | `string` (sensitive) | — | **Yes** | Your DigitalOcean API token. Marked `sensitive` so it never appears in logs or `terraform output` |
| `project_name` | `string` | — | **Yes** | Prefix for all resource names (Droplet, firewall, containers) |
| `region` | `string` | `sgp1` | No | Singapore datacenter — closest to you |
| `droplet_size` | `string` | `s-2vcpu-4gb` | No | The $24/mo plan (4GB RAM, 2 CPUs, 80GB disk) |
| `droplet_image` | `string` | `ubuntu-24-04-x64` | No | Ubuntu 24.04 LTS base OS |
| `droplet_name` | `string` | `{project_name}-dev-db` | No | Droplet hostname (auto-computed from `project_name` if not set) |
| `kafka_topics` | `list(object)` | — | **Yes** | Kafka topics to create after provisioning. Each object has `name` (required), `partitions` (default 1), `replication_factor` (default 1) |

You set these in `terraform.tfvars` (gitignored) or pass them via `-var` flags.

---

## data.tf — Auto-detect Your IP

```hcl
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip        = trimspace(data.http.my_ip.response_body)
  droplet_name = var.droplet_name != "" ? var.droplet_name : "${var.project_name}-dev-db"
}
```

- Calls an AWS service that returns your public IP address as plain text
- `trimspace()` removes the trailing newline
- `local.my_ip` is used by `firewall.tf` so you never need to manually type your IP
- `local.droplet_name` computes the Droplet hostname from `project_name` (or uses a custom `droplet_name` if provided)
- **Re-detected on every `terraform apply`** — if you change networks (home → office → coffee shop), just re-apply and the firewall updates automatically

---

## main.tf — The Core Infrastructure

### SSH Key (lines 3–16)

```hcl
resource "tls_private_key" "droplet" {
  algorithm = "ED25519"
}
```

Generates an ED25519 SSH key pair in memory. No manual `ssh-keygen` needed.

```hcl
resource "digitalocean_ssh_key" "droplet" {
  name       = local.droplet_name
  public_key = tls_private_key.droplet.public_key_openssh
}
```

Uploads the **public** key to your DigitalOcean account.

```hcl
resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.droplet.private_key_openssh
  filename        = "${path.module}/generated/id_ed25519"
  file_permission = "0600"
}
```

Saves the **private** key to `generated/id_ed25519` on your laptop with `0600` permissions (owner-only read/write). Uses `local_sensitive_file` (not `local_file`) so the key content is never printed in Terraform output.

### Droplet (lines 20–52)

```hcl
resource "digitalocean_droplet" "main" {
  name     = local.droplet_name
  region   = var.region
  size     = var.droplet_size
  image    = var.droplet_image
  ssh_keys = [digitalocean_ssh_key.droplet.fingerprint]
  ...
}
```

Creates the server with the generated SSH key attached. Password auth is disabled — only SSH key access works.

#### connection block

```hcl
connection {
  type        = "ssh"
  user        = "root"
  private_key = tls_private_key.droplet.private_key_openssh
  host        = self.ipv4_address
}
```

Tells Terraform how to SSH into the Droplet for the provisioners below. `self.ipv4_address` refers to this Droplet's own IP (available after creation).

#### provisioner "file" (lines 35–40)

```hcl
provisioner "file" {
  content = templatefile("${path.module}/templates/cloud-docker-compose.yml.tpl", {
    droplet_ip   = self.ipv4_address
    project_name = var.project_name
  })
  destination = "/root/docker-compose.yml"
}
```

- Reads `templates/cloud-docker-compose.yml.tpl`
- Replaces `${droplet_ip}` with the actual Droplet IP and `${project_name}` with the project name
- Uploads the rendered file to `/root/docker-compose.yml` on the Droplet

#### provisioner "remote-exec" (lines 43–50)

```hcl
provisioner "remote-exec" {
  inline = [
    "cloud-init status --wait",
    "curl -fsSL https://get.docker.com | sh",
    "systemctl enable --now docker",
    "cd /root && docker compose up -d",
  ]
}
```

Runs these commands on the Droplet in order:

1. `cloud-init status --wait` — waits for Ubuntu's initial boot setup to finish (apt locks, etc.)
2. `curl -fsSL https://get.docker.com | sh` — installs Docker Engine
3. `systemctl enable --now docker` — starts Docker and enables it on boot
4. `cd /root && docker compose up -d` — starts MongoDB + Kafka containers in detached mode

### Kafka Topics (lines 56–80)

```hcl
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
      [
        "for i in $(seq 1 12); do docker exec ${var.project_name}-kafka-cloud kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1 && break || sleep 5; done",
      ],
      [for t in var.kafka_topics :
        "docker exec ${var.project_name}-kafka-cloud kafka-topics --create --topic ${t.name} --partitions ${t.partitions} --replication-factor ${t.replication_factor} --bootstrap-server localhost:9092 --if-not-exists"
      ]
    )
  }
}
```

Creates Kafka topics defined in `terraform.tfvars` after the Droplet is fully provisioned. Uses `terraform_data` (the modern replacement for `null_resource`) to keep topic creation **decoupled** from the Droplet provisioner.

- **`depends_on`** — ensures the Droplet (and its Docker install) is complete before running
- **`triggers_replace`** — recreates this resource when the topic list changes or the Droplet is rebuilt (new ID). This means you can add topics without destroying the Droplet
- **Readiness loop** — polls `kafka-broker-api-versions` every 5 seconds, up to 12 attempts (60s), waiting for Kafka to be ready
- **`--if-not-exists`** — makes topic creation idempotent; existing topics are skipped

**Behavior on subsequent applies:**

| Scenario | What happens |
|----------|-------------|
| No changes to topics or Droplet | Nothing — resource already exists, triggers unchanged |
| New topic added to tfvars | Resource recreated → all topics re-run → existing ones skipped, new one created |
| Topic removed from tfvars | **Not deleted** from Kafka — persists until Droplet is destroyed |
| Droplet destroyed & recreated | Resource recreated → all topics created on the fresh Droplet |

### Generate Local Compose (lines 84–90)

```hcl
resource "local_file" "local_compose" {
  content = templatefile("${path.module}/templates/local-docker-compose.yml.tpl", {
    droplet_ip   = digitalocean_droplet.main.ipv4_address
    project_name = var.project_name
  })
  filename = "${path.module}/generated/local-docker-compose.yml"
}
```

- Reads `templates/local-docker-compose.yml.tpl`
- Injects the Droplet IP so Kafka-UI knows where to connect
- Writes to `generated/local-docker-compose.yml` on your laptop

---

## firewall.tf — Network Security

```hcl
resource "digitalocean_firewall" "dev_database" {
  name        = "${local.droplet_name}-fw"
  droplet_ids = [digitalocean_droplet.main.id]
  ...
}
```

A cloud firewall attached to the Droplet. Only your laptop's IP (`local.my_ip`) can reach it.

### Inbound Rules

| Rule | Port | Source | Purpose |
|------|------|--------|---------|
| SSH | 22 | Your IP `/32` | Remote access to the Droplet |
| MongoDB | 27017 | Your IP `/32` | Your app connects to MongoDB |
| Kafka | 9092 | Your IP `/32` | Your app and Kafka-UI connect to Kafka |
| Kafka JMX | 9101 | Your IP `/32` | Monitoring metrics |

The `/32` CIDR suffix means "exactly this one IP address." Everyone else on the internet is blocked.

### Outbound Rules

| Protocol | Port Range | Destination | Purpose |
|----------|-----------|-------------|---------|
| TCP | 1–65535 | `0.0.0.0/0`, `::/0` | Docker image pulls, apt updates |
| UDP | 1–65535 | `0.0.0.0/0`, `::/0` | DNS resolution, NTP |
| ICMP | — | `0.0.0.0/0`, `::/0` | Ping (health checks) |

---

## outputs.tf — Post-Apply Output

After `terraform apply` completes, these values are printed to your terminal:

| Output | Example | Purpose |
|--------|---------|---------|
| `droplet_ip` | `152.42.175.220` | The Droplet's public IP |
| `ssh_command` | `ssh -i generated/id_ed25519 root@152.42.175.220` | Ready-to-paste SSH command |
| `mongodb_connection_string` | `mongodb://152.42.175.220:27017/?directConnection=true` | For your app's `.env` file |
| `kafka_broker` | `152.42.175.220:9092` | For your app's `.env` file |
| `my_detected_ip` | `110.168.xxx.xxx` | Confirms which IP was used for the firewall |

You can view these again anytime with `terraform output`.

---

## Templates (.tpl files)

### templates/cloud-docker-compose.yml.tpl

Runs **on the Droplet**. Contains:

- **MongoDB 7.0** — port 27017, data persisted in a Docker volume
- **Kafka 7.6.0** (KRaft mode, no ZooKeeper) — port 9092 for brokers, port 9101 for JMX
- `${droplet_ip}` is injected into `KAFKA_ADVERTISED_LISTENERS` and `KAFKA_JMX_HOSTNAME` so your laptop can reach Kafka by its public IP
- Both containers share a `cloud-net` bridge network

### templates/local-docker-compose.yml.tpl

Runs **on your laptop**. Contains:

- **Jaeger 2.6.0** — OpenTelemetry collector + UI on port 16686
- **Kafka-UI** — web dashboard on port 9333, pre-configured with `KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: "${droplet_ip}:9092"`
- **Redis 7** — port 6379, data persisted in a Docker volume

The bottom of the file includes a comment block with all connection strings for quick reference.
