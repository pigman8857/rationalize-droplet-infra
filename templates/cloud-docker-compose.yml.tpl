# ─── CLOUD ENVIRONMENT (DigitalOcean) ───────────────────────
# Managed by Terraform — do not edit manually
# ────────────────────────────────────────────────────────────

services:
  # ─── MongoDB ─────────────────────────────────────────────
  mongodb:
    image: mongo:7.0
    container_name: rationalization-mongodb-cloud
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    environment:
      TZ: Asia/Bangkok
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "db.runCommand({ ping: 1 })"]
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - cloud-net

  # ─── Kafka (KRaft mode) ──────────────────────────────────
  kafka:
    image: confluentinc/cp-kafka:7.6.0
    container_name: rationalization-kafka-cloud
    ports:
      - "9092:9092"
      - "9101:9101"
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT"
      KAFKA_ADVERTISED_LISTENERS: "PLAINTEXT://kafka:29092,PLAINTEXT_HOST://${droplet_ip}:9092"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_JMX_PORT: 9101
      KAFKA_JMX_HOSTNAME: ${droplet_ip}
      KAFKA_PROCESS_ROLES: "broker,controller"
      KAFKA_CONTROLLER_QUORUM_VOTERS: "1@kafka:29093"
      KAFKA_LISTENERS: "PLAINTEXT://kafka:29092,CONTROLLER://kafka:29093,PLAINTEXT_HOST://0.0.0.0:9092"
      KAFKA_INTER_BROKER_LISTENER_NAME: "PLAINTEXT"
      KAFKA_CONTROLLER_LISTENER_NAMES: "CONTROLLER"
      KAFKA_LOG_DIRS: "/tmp/kraft-combined-logs"
      CLUSTER_ID: "MkU3OEVBNTcwNTJENDM3Ym"
    restart: unless-stopped
    networks:
      - cloud-net

volumes:
  mongodb_data:

networks:
  cloud-net:
    driver: bridge
