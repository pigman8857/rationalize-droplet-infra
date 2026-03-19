# Plan: Auto-create Kafka Topic After Provisioning

## Goal

Automatically create the topic `esb.portal.user.consume.v1` after Kafka is running on the Droplet, so every `terraform apply` yields a ready-to-use broker with the required topic.

## Approach: `terraform_data` with `remote-exec` provisioner

Use a `terraform_data` resource that depends on the Droplet being fully provisioned. This keeps topic creation decoupled from the Docker install step and makes it easy to add more topics later.

### Why `terraform_data` over `null_resource`?

- Built-in to Terraform since 1.4 — no extra provider required (we already require `>= 1.5`).
- `null_resource` + `hashicorp/null` is legacy; `terraform_data` is the recommended replacement.
- Uses `triggers_replace` which accepts any type (no need to `jsonencode`).

### Why not the Kafka Terraform provider?

- Adds a provider dependency and requires the broker to be network-reachable from the machine running Terraform at plan time.
- Overkill for a single-broker ephemeral dev setup.

### Why a separate resource instead of adding to the existing `remote-exec`?

- Keeps concerns separated (infra setup vs. application-level seeding).
- Can be extended independently (e.g., add more topics, change partitions) without re-triggering Docker install.
- Re-runs only when the topic list or Droplet changes.

## Changes

### 1. `variables.tf` — add `kafka_topics` variable

```hcl
variable "kafka_topics" {
  description = "Kafka topics to create after provisioning"
  type = list(object({
    name               = string
    partitions         = optional(number, 1)
    replication_factor = optional(number, 1)
  }))
  default = [
    { name = "esb.portal.user.consume.v1" },
    { name = "another.topic.v1" },
    { name = "yet.another.topic.v1", partitions = 3 },
  ]
}
```

This makes topic creation data-driven. Adding a new topic is a one-line change in `terraform.tfvars` or the default list.

### 2. `main.tf` — add `terraform_data.kafka_topics`

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
```

Key details:
- **Readiness check**: Polls `kafka-broker-api-versions` every 5s (up to 60s) before attempting topic creation. This is more reliable than a fixed `sleep`.
- **`--if-not-exists`**: Makes topic creation idempotent.
- **`triggers_replace`**: Re-runs when the topic list changes or the Droplet is recreated. Accepts any type directly — no `jsonencode` needed.

## Files touched

| File | Change |
|------|--------|
| `variables.tf` | Add `kafka_topics` variable |
| `main.tf` | Add `terraform_data.kafka_topics` |

## Adding a new topic later

No need to destroy and re-apply. Just:

1. Add the new topic to the `kafka_topics` variable default list (or `terraform.tfvars`).
2. Run `terraform apply`.

Because `triggers_replace` includes `var.kafka_topics`, changing the list causes Terraform to recreate the `terraform_data.kafka_topics` resource and re-run the provisioner. The `--if-not-exists` flag ensures existing topics are skipped — only the new topic gets created.

## Verification

After `terraform apply`:
```bash
ssh -i generated/id_ed25519 root@<droplet_ip> \
  "docker exec <project_name>-kafka-cloud kafka-topics --list --bootstrap-server localhost:9092"
```

Expected output should include `esb.portal.user.consume.v1`.
