variable "do_token" {
  description = "DigitalOcean Personal Access Token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sgp1"
}

variable "droplet_size" {
  description = "Droplet size slug"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "droplet_image" {
  description = "Droplet OS image"
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
}

variable "droplet_name" {
  description = "Droplet hostname (defaults to {project_name}-dev-db)"
  type        = string
  default     = ""
}

variable "kafka_topics" {
  description = "Kafka topics to create after provisioning"
  type = list(object({
    name               = string
    partitions         = optional(number, 1)
    replication_factor = optional(number, 1)
  }))
}
