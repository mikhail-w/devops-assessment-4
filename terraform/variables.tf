# Variables for the Twoge application deployment

variable "image_tag" {
  description = "The tag of the Docker image to deploy"
  type        = string
}

variable "docker_username" {
  description = "Docker Hub username"
  type        = string
}

# Optional: You can add more variables for customization
variable "postgres_version" {
  description = "The version of PostgreSQL to use"
  type        = string
  default     = "13"
}

variable "twoge_replicas" {
  description = "Number of replicas for the Twoge application"
  type        = number
  default     = 2
}

variable "postgres_replicas" {
  description = "Number of replicas for PostgreSQL"
  type        = number
  default     = 1
}

variable "postgres_storage" {
  description = "Storage size for PostgreSQL in Gi"
  type        = string
  default     = "1Gi"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "twoge-cluster-mw"
}

variable "region" {
  description = "AWS region where the cluster is deployed"
  type        = string
  default     = "us-east-1"
}

variable "namespace_name" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "twoge-app"
}

variable "db_user_base64" {
  description = "Base64 encoded database username"
  type        = string
  default     = "cG9zdGdyZXM="  # "postgres" in base64
}

variable "db_password_base64" {
  description = "Base64 encoded database password"
  type        = string
  default     = "cG9zdGdyZXM="  # "postgres" in base64
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "twoge"
}

variable "db_port" {
  description = "Database port"
  type        = string
  default     = "5432"
}