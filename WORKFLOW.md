# Workflow Diagrams

## Terraform Resource Dependency Graph

How Terraform resources depend on each other. Terraform builds resources in parallel where possible, respecting these dependencies.

```mermaid
graph TD
    subgraph Inputs
        TOKEN[var.do_token]
        REGION[var.region]
        SIZE[var.droplet_size]
        IMAGE[var.droplet_image]
        NAME[var.droplet_name]
    end

    subgraph "data.tf — Auto-detect IP"
        HTTP[data.http.my_ip<br/>calls checkip.amazonaws.com]
        LOCAL_IP[local.my_ip<br/>trimmed IP string]
        HTTP --> LOCAL_IP
    end

    subgraph "main.tf — SSH Key"
        TLS[tls_private_key.droplet<br/>generates ED25519 key pair]
        DO_SSH[digitalocean_ssh_key.droplet<br/>uploads public key to DO]
        SSH_FILE[local_sensitive_file.ssh_private_key<br/>saves private key to generated/id_ed25519]
        TLS --> DO_SSH
        TLS --> SSH_FILE
    end

    subgraph "main.tf — Droplet"
        DROPLET[digitalocean_droplet.main<br/>creates Ubuntu 24.04 server]
        UPLOAD["provisioner file<br/>uploads docker-compose.yml<br/>(from cloud template)"]
        REMOTE["provisioner remote-exec<br/>1. cloud-init wait<br/>2. install Docker<br/>3. docker compose up -d"]
        DROPLET --> UPLOAD --> REMOTE
    end

    subgraph "main.tf — Local Compose"
        LOCAL_COMPOSE[local_file.local_compose<br/>writes generated/local-docker-compose.yml]
    end

    subgraph "firewall.tf"
        FW[digitalocean_firewall.dev_database<br/>inbound: SSH, MongoDB, Kafka, JMX<br/>only from your IP]
    end

    subgraph "outputs.tf"
        OUT_IP[output: droplet_ip]
        OUT_SSH[output: ssh_command]
        OUT_MONGO[output: mongodb_connection_string]
        OUT_KAFKA[output: kafka_broker]
        OUT_MY_IP[output: my_detected_ip]
    end

    TOKEN --> DROPLET
    REGION --> DROPLET
    SIZE --> DROPLET
    IMAGE --> DROPLET
    NAME --> DROPLET
    DO_SSH --> DROPLET
    TLS --> DROPLET

    DROPLET --> LOCAL_COMPOSE
    DROPLET --> FW
    LOCAL_IP --> FW

    DROPLET --> OUT_IP
    DROPLET --> OUT_SSH
    DROPLET --> OUT_MONGO
    DROPLET --> OUT_KAFKA
    LOCAL_IP --> OUT_MY_IP

    subgraph Templates
        TPL_CLOUD[cloud-docker-compose.yml.tpl<br/>MongoDB + Kafka]
        TPL_LOCAL[local-docker-compose.yml.tpl<br/>Jaeger + Kafka-UI + Redis]
    end

    TPL_CLOUD --> UPLOAD
    TPL_LOCAL --> LOCAL_COMPOSE
```

---

## Setup Workflow (Step by Step)

What happens from start to finish when you set up and use this project.

```mermaid
flowchart TD
    START([Start]) --> INSTALL[Install Terraform >= 1.5]
    INSTALL --> CREATE_TOKEN[Create DigitalOcean API token<br/>with 19 custom scopes]
    CREATE_TOKEN --> CLONE[Clone this repo]
    CLONE --> TFVARS["Create terraform.tfvars<br/>do_token = your_token"]
    TFVARS --> INIT["terraform init<br/>downloads providers:<br/>digitalocean, local, tls, http"]
    INIT --> PLAN["terraform plan<br/>preview: 1 SSH key, 1 Droplet,<br/>1 firewall, 2 local files"]
    PLAN --> REVIEW{Review plan<br/>looks good?}
    REVIEW -- No --> EDIT[Edit variables.tf<br/>or terraform.tfvars]
    EDIT --> PLAN
    REVIEW -- Yes --> APPLY["terraform apply<br/>type 'yes'"]

    APPLY --> PHASE1

    subgraph PHASE1 ["Phase 1 — Parallel (no dependencies)"]
        direction LR
        P1A["Detect your public IP<br/>(data.http.my_ip)"]
        P1B["Generate SSH key pair<br/>(tls_private_key)"]
    end

    PHASE1 --> PHASE2

    subgraph PHASE2 ["Phase 2 — Depends on SSH key"]
        direction LR
        P2A["Upload public key to DO<br/>(digitalocean_ssh_key)"]
        P2B["Save private key locally<br/>(generated/id_ed25519)"]
    end

    PHASE2 --> PHASE3

    subgraph PHASE3 ["Phase 3 — Create Droplet"]
        P3A["Provision Droplet<br/>Ubuntu 24.04, sgp1, 4GB RAM"]
    end

    PHASE3 --> PHASE4

    subgraph PHASE4 ["Phase 4 — Provisioners (on Droplet, sequential)"]
        direction TB
        P4A["Upload docker-compose.yml<br/>(template with real IP injected)"]
        P4B["cloud-init status --wait"]
        P4C["Install Docker Engine"]
        P4D["Enable Docker on boot"]
        P4E["docker compose up -d<br/>(MongoDB + Kafka start)"]
        P4A --> P4B --> P4C --> P4D --> P4E
    end

    PHASE4 --> PHASE5

    subgraph PHASE5 ["Phase 5 — Parallel (depends on Droplet IP)"]
        direction LR
        P5A["Create firewall<br/>(your IP only on ports<br/>22, 9092, 9101, 27017)"]
        P5B["Generate local-docker-compose.yml<br/>(Droplet IP injected)"]
    end

    PHASE5 --> OUTPUT["Terraform prints outputs:<br/>droplet_ip, ssh_command,<br/>mongodb_connection_string,<br/>kafka_broker, my_detected_ip"]

    OUTPUT --> LOCAL_UP["docker compose -f<br/>generated/local-docker-compose.yml up -d<br/>(starts Jaeger, Kafka-UI, Redis)"]
    LOCAL_UP --> ENV["Update your app .env:<br/>MongoDB → droplet_ip:27017<br/>Kafka → droplet_ip:9092<br/>Redis → localhost:6379<br/>Jaeger → localhost:4317"]
    ENV --> DEV([Ready to develop])

    style PHASE1 fill:#e8f4f8,stroke:#0969da
    style PHASE2 fill:#e8f4f8,stroke:#0969da
    style PHASE3 fill:#dafbe1,stroke:#1a7f37
    style PHASE4 fill:#fff8c5,stroke:#9a6700
    style PHASE5 fill:#e8f4f8,stroke:#0969da
```

---

## Day-to-Day Operations

```mermaid
flowchart TD
    subgraph "IP Changed (new network)"
        IP_CHANGE[Connection timeout] --> REAPPLY["terraform apply<br/>(auto-detects new IP,<br/>updates firewall only)"]
        REAPPLY --> WORKING[Connection restored]
    end

    subgraph "Done for the day"
        STOP_LOCAL["docker compose -f<br/>generated/local-docker-compose.yml down"]
        STOP_LOCAL --> KEEP{Keep Droplet<br/>running?}
        KEEP -- "Yes (data persists)" --> DONE([Done])
        KEEP -- "No (save money)" --> DESTROY["terraform destroy<br/>removes Droplet + firewall + SSH key"]
        DESTROY --> DONE
    end

    subgraph "Next day (after destroy)"
        NEXT["terraform apply<br/>(rebuilds everything from scratch)"] --> FRESH([Fresh Droplet + empty databases])
    end
```
