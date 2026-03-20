# CLAUDE.md

## Project overview

Terraform automation for provisioning a DigitalOcean Droplet running Kafka and MongoDB as Docker containers. Lightweight services (Jaeger, Redis, Kafka-UI) run locally on the developer's laptop.

The Droplet is **ephemeral** — created at the start of the day, destroyed at the end. Data is lost on every destroy; this is acceptable for development.

## Tech stack

- **Terraform** >= 1.5 (HCL)
- **Providers:** digitalocean (~> 2.36), local (~> 2.5), tls (~> 4.0), http (~> 3.4)
- **Droplet OS:** Ubuntu 24.04 LTS
- **Services on Droplet:** MongoDB 7.0, Kafka 7.6.0 (via Docker Compose)
- **Services on laptop:** Jaeger, Redis, Kafka-UI (via generated Docker Compose)

## File layout

- `main.tf` — SSH key, Droplet, Docker install, compose upload, Kafka topic creation
- `variables.tf` — input variables (no defaults for `do_token`, `project_name`, `kafka_topics`)
- `terraform.tfvars` — secrets and config (gitignored, never commit)
- `firewall.tf` — firewall rules scoped to the developer's IP
- `data.tf` — auto-detects laptop's public IP
- `outputs.tf` — connection strings, SSH command
- `templates/` — Docker Compose templates for cloud and local
- `docs/` — documentation (TERRAFORM_FILES.md, WORKFLOW.md, plans/)
- `generated/` — Terraform-generated files (gitignored)

## Key patterns

- `terraform.tfvars` is the single source of truth for Kafka topics — no defaults in `variables.tf`
- `terraform_data` resources are used for post-provisioning tasks (e.g., Kafka topic creation) to avoid re-triggering Droplet provisioning
- All resource names are prefixed with `var.project_name`

## Commit conventions

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `refactor:`, `docs:`, etc.
- Keep subject line under 72 characters, imperative mood
- Body explains "why", not "what"

## Things to avoid

- Never commit `terraform.tfvars` — it contains the DO API token
- Never commit files in `generated/` — they contain SSH private keys
- Never reference or link to company-owned repos
- Do not run `git add/commit` — only provide commit message text for the user
