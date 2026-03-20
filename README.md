# Droplet Infrastructure

Terraform automation for provisioning a DigitalOcean Droplet running **Kafka** and **MongoDB** as Docker containers — offloading heavy services from your laptop for local development.

## Motivation

A typical development setup requires 5 infrastructure services running simultaneously:

| Service      | Role                             |
| ------------ | -------------------------------- |
| **MongoDB**  | Primary database                 |
| **Kafka**    | Event streaming / message broker |
| **Jaeger**   | OpenTelemetry tracing            |
| **Kafka-UI** | Web dashboard for Kafka          |
| **Redis**    | Caching                          |

Running all 5 as Docker containers on a single laptop consumes too much RAM, causing slowdowns or crashes. **Kafka and MongoDB are the heaviest** — Kafka alone needs ~1–2 GB, and MongoDB's working set grows with data.

The solution: move Kafka and MongoDB to a **$24/month DigitalOcean Droplet** (4 GB RAM, 2 CPUs, 80 GB disk) in Singapore, and keep the lightweight services (Jaeger, Kafka-UI, Redis) running locally. This gives your laptop breathing room while keeping latency acceptable for development.

Since the Droplet is only needed during active development, it is **created at the start of the day and destroyed at the end** to avoid paying for idle hours. Running ~8–10 hours/day instead of 24 saves roughly 60–70% on the $24/mo plan (DigitalOcean bills hourly). This repo automates that entire hybrid setup with a single `terraform apply` — no manual server configuration, no copy-pasting IPs, no remembering firewall rules. Tearing down is equally simple: `terraform destroy`.

> **Note:** Because the Droplet is ephemeral, MongoDB data and Kafka topics are **lost on every destroy**. This is fine for development — seed scripts or application startup should recreate any required data.

## Architecture

```
┌─────────────────────────────┐        ┌──────────────────────────────────┐
│        Your Laptop          │        │   DigitalOcean Droplet (4GB)     │
│                             │        │                                  │
│  ┌───────────────────────┐  │        │  ┌────────────────────────────┐  │
│  │ Jaeger     :16686     │  │        │  │ MongoDB 7.0    :27017     │  │
│  │ Redis      :6379      │  │        │  │ Kafka 7.6.0    :9092      │  │
│  │ Kafka-UI   :9333      │──┼───────►│  └────────────────────────────┘  │
│  └───────────────────────┘  │        │                                  │
│                             │        │  Firewall: only YOUR IP allowed  │
│  Your application            │        └──────────────────────────────────┘
│                             │
└─────────────────────────────┘
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Docker](https://docs.docker.com/get-docker/) (on your laptop, for local services)
- A [DigitalOcean account](https://cloud.digitalocean.com/) with a Personal Access Token

## Quick Start

### 1. Clone and enter the repo

```bash
git clone <your-repo-url>
cd droplet-infra
```

### 2. Add your DigitalOcean token

Create a `terraform.tfvars` file (this file is gitignored and will never be committed):

```hcl
do_token     = "dop_v1_your_token_here"
project_name = "myapp"   # prefix for all resource names

kafka_topics = [
  { name = "esb.portal.user.consume.v1" },
]
```

> **How to create a token with minimum required scopes:**
>
> 1. Go to **DigitalOcean Console** → **API** → **Tokens** → **Generate New Token**
> 2. Name it (e.g. `droplet-infra-terraform`)
> 3. Choose **Custom Scopes** (not Full Access)
> 4. Enable these scopes (19 total):
>
> **Full Access (read + write):**
>
> | Scope      | Permissions                         | Why                                                            |
> | ---------- | ----------------------------------- | -------------------------------------------------------------- |
> | `actions`  | read                                | Terraform polls action status to know when operations complete |
> | `droplet`  | create, read, update, delete, admin | Create, manage, and destroy the Droplet                        |
> | `firewall` | create, read, update, delete        | Create and update the firewall rules                           |
> | `regions`  | read                                | Terraform validates the region (`sgp1`) exists                 |
> | `sizes`    | read                                | Terraform validates the Droplet size (`s-2vcpu-4gb`) exists    |
> | `ssh_key`  | create, read, update, delete        | Upload and manage the generated SSH key                        |
>
> **Read-only Access:**
>
> | Scope      | Permissions | Why                                                  |
> | ---------- | ----------- | ---------------------------------------------------- |
> | `image`    | read        | Terraform looks up the OS image (`ubuntu-24-04-x64`) |
> | `snapshot` | read        | Required by the DigitalOcean Terraform provider      |
> | `vpc`      | read        | Terraform reads default VPC info for the Droplet     |
>
> 5. Set an expiry (e.g. 90 days) for safety
> 6. Copy the token — you won't see it again
>
> Using custom scopes instead of Full Access follows the **principle of least privilege** — if the token ever leaks, the attacker can only touch Droplets, SSH keys, and firewalls, not your entire DO account.

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Preview what will be created

```bash
terraform plan
```

You should see: 1 SSH key, 1 Droplet, 1 Firewall, 1 Kafka topic provisioner, 2 local files.

### 5. Deploy

```bash
terraform apply
```

Type `yes` when prompted. This will:

1. Auto-detect your laptop's public IP (for firewall rules)
2. Generate an SSH key pair
3. Create the Droplet (Ubuntu 24.04, 4GB RAM, Singapore region)
4. Install Docker on the Droplet
5. Deploy MongoDB and Kafka via Docker Compose on the Droplet
6. Create Kafka topics defined in `terraform.tfvars`
7. Create a firewall allowing only your IP
8. Generate `generated/local-docker-compose.yml` with the Droplet IP pre-filled

Once complete, Terraform prints the connection info:

```
droplet_ip                 = "xxx.xxx.xxx.xxx"
ssh_command                = "ssh -i generated/id_ed25519 root@xxx.xxx.xxx.xxx"
mongodb_connection_string  = "mongodb://xxx.xxx.xxx.xxx:27017/?directConnection=true"
kafka_broker               = "xxx.xxx.xxx.xxx:9092"
my_detected_ip             = "your.laptop.ip.here"
```

### 6. Start local services

```bash
docker compose -f generated/local-docker-compose.yml up -d
```

This starts Jaeger, Redis, and Kafka-UI on your laptop. Kafka-UI is already configured to connect to the Droplet's Kafka broker.

### 7. Configure your application

Update your application's `.env` or config to point to:

| Service   | Address                                               |
| --------- | ----------------------------------------------------- |
| MongoDB   | `mongodb://<droplet_ip>:27017/?directConnection=true` |
| Kafka     | `<droplet_ip>:9092`                                   |
| Redis     | `localhost:6379`                                      |
| Jaeger    | `localhost:4317` (OTLP gRPC)                          |
| Kafka UI  | `http://localhost:9333`                               |
| Jaeger UI | `http://localhost:16686`                              |

## Common Operations

### SSH into the Droplet

```bash
ssh -i generated/id_ed25519 root@<droplet_ip>
```

Or copy the command directly from the Terraform output:

```bash
terraform output ssh_command
```

### Check Docker containers on the Droplet

```bash
ssh -i generated/id_ed25519 root@<droplet_ip> "docker ps"
```

### View logs on the Droplet

```bash
ssh -i generated/id_ed25519 root@<droplet_ip> "docker compose logs -f"
```

### Add a new Kafka topic

Add the topic to `kafka_topics` in `terraform.tfvars`:

```hcl
kafka_topics = [
  { name = "esb.portal.user.consume.v1" },
  { name = "new.topic.v1" },
  { name = "high.throughput.topic.v1", partitions = 6 },
]
```

Then run `terraform apply`. No destroy needed — only the topic provisioner is re-run. Existing topics are skipped (`--if-not-exists`).

> **Note:** Removing a topic from tfvars does **not** delete it from Kafka. It simply won't be recreated on the next fresh Droplet.

### IP address changed (e.g. moved to a different network)

Just re-apply — Terraform auto-detects your new IP and updates the firewall. The Droplet itself is **not** recreated:

```bash
terraform apply
```

### View current outputs again

```bash
terraform output
```

### Destroy everything

```bash
terraform destroy
```

Type `yes` to confirm. This removes the Droplet, firewall, and SSH key from DigitalOcean.

## File Structure

```
droplet-infra/
├── .gitignore              # Ignores state, tfvars, generated/
├── versions.tf             # Terraform & provider version constraints
├── variables.tf            # Input variables (do_token, project_name, region, size, kafka_topics, etc.)
├── data.tf                 # Auto-detects your laptop's public IP
├── main.tf                 # SSH key, Droplet, Docker install, compose upload, Kafka topic creation
├── firewall.tf             # Firewall rules (your IP only)
├── outputs.tf              # Connection strings, SSH command
├── templates/
│   ├── cloud-docker-compose.yml.tpl   # Droplet compose (MongoDB + Kafka)
│   └── local-docker-compose.yml.tpl   # Laptop compose (Jaeger + Redis + Kafka-UI)
├── terraform.tfvars        # Your DO token + kafka_topics (gitignored, create manually)
├── docs/
│   ├── TERRAFORM_FILES.md  # Detailed explanation of every Terraform file and setting
│   ├── WORKFLOW.md          # Mermaid diagrams (dependency graph, setup flow, daily ops)
│   └── plans/               # Implementation plans and design decisions
└── generated/              # Created by Terraform (gitignored)
    ├── id_ed25519           # SSH private key
    └── local-docker-compose.yml  # Rendered local compose
```

## Customization

Override defaults in `terraform.tfvars`:

```hcl
do_token     = "dop_v1_your_token_here"
project_name = "myapp"                   # required: prefix for all resource names
region       = "sgp1"                    # default: Singapore
droplet_size = "s-2vcpu-4gb"             # default: 4GB RAM / 2 CPUs ($24/mo)
droplet_name = ""                        # default: {project_name}-dev-db

kafka_topics = [                         # required: topics to create after provisioning
  { name = "esb.portal.user.consume.v1" },
]
```

## Troubleshooting

| Problem                                | Solution                                                                                                |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `terraform apply` hangs on provisioner | The Droplet may still be booting. Wait a few minutes. If it persists, `terraform destroy` and re-apply. |
| Connection timeout after apply         | Your public IP likely changed. Run `terraform apply` to update the firewall.                            |
| `docker compose` not found on Droplet  | SSH in and run: `curl -fsSL https://get.docker.com \| sh`                                               |
| Kafka-UI can't connect to broker       | Verify the Droplet firewall allows your IP on port 9092: `terraform output my_detected_ip`              |
| MongoDB extension can't connect        | Use the full connection string with `?directConnection=true`                                            |
