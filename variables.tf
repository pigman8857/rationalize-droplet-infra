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

variable "droplet_name" {
  description = "Droplet hostname"
  type        = string
  default     = "rationalization-dev-db"
}
