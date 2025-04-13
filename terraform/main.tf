# Configure AWS provider
provider "aws" {
  region = var.region
}

# Reference existing EKS cluster
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

# Configure Kubernetes provider to communicate with the EKS cluster
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.cluster.name]
    command     = "aws"
  }
}

# Create namespace for application resources
resource "kubernetes_namespace" "twoge_app" {
  metadata {
    name = var.namespace_name
    labels = {
      name = var.namespace_name
    }
  }
}

# Create ConfigMap for non-sensitive configuration
resource "kubernetes_config_map" "twoge_config" {
  metadata {
    name      = "twoge-config"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }

  data = {
    DB_HOST     = "postgres-service"
    DB_PORT     = var.db_port
    DB_DATABASE = var.db_name
  }
}

# Create Secret for sensitive configuration
resource "kubernetes_secret" "twoge_secrets" {
  metadata {
    name      = "twoge-secrets"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }

  data = {
    DB_USER     = var.db_user_base64
    DB_PASSWORD = var.db_password_base64
  }

  type = "Opaque"
}

# Create Storage Class for persistent volume
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"
  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }
  volume_binding_mode = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

# Create Resource Quota for the namespace
resource "kubernetes_resource_quota" "twoge_quota" {
  metadata {
    name      = "twoge-quota"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"    = "1"
      "requests.memory" = "1Gi"
      "limits.cpu"      = "2"
      "limits.memory"   = "2Gi"
      "pods"            = "10"
    }
  }
}

# Create Persistent Volume Claim for PostgreSQL
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.postgres_storage
      }
    }
    storage_class_name = kubernetes_storage_class.gp3.metadata[0].name
  }
}

# Create PostgreSQL Deployment
resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres-deployment"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
    labels = {
      app = "postgres"
    }
  }

  spec {
    replicas = var.postgres_replicas
    selector {
      match_labels = {
        app = "postgres"
      }
    }
    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }
      spec {
        container {
          name  = "postgres"
          image = "postgres:${var.postgres_version}"
          port {
            container_port = 5432
          }
          resources {
            requests = {
              memory = "256Mi"
              cpu    = "200m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.twoge_secrets.metadata[0].name
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.twoge_secrets.metadata[0].name
                key  = "DB_PASSWORD"
              }
            }
          }
          env {
            name = "POSTGRES_DB"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.twoge_config.metadata[0].name
                key  = "DB_DATABASE"
              }
            }
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
          }
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "postgres"
          }
        }
        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Create PostgreSQL Service
resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres-service"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }
  spec {
    selector = {
      app = "postgres"
    }
    port {
      port        = 5432
      target_port = 5432
    }
    type = "ClusterIP"
  }
}

# Create Twoge Application Deployment
resource "kubernetes_deployment" "twoge" {
  metadata {
    name      = "twoge-deployment"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
    labels = {
      app = "twoge"
    }
  }

  spec {
    replicas = var.twoge_replicas
    selector {
      match_labels = {
        app = "twoge"
      }
    }
    template {
      metadata {
        labels = {
          app = "twoge"
        }
      }
      spec {
        container {
          name  = "twoge"
          # Use the dynamic image tag from CI/CD
          image = "${var.docker_username}/twoge:${var.image_tag}"
          port {
            container_port = 8080
          }
          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "200m"
            }
          }
          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          env {
            name  = "FLASK_APP"
            value = "app.py"
          }
          env {
            name  = "FLASK_RUN_HOST"
            value = "0.0.0.0"
          }
          env {
            name  = "FLASK_RUN_PORT"
            value = "8080"
          }
          env {
            name = "DB_HOST"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.twoge_config.metadata[0].name
                key  = "DB_HOST"
              }
            }
          }
          env {
            name = "DB_PORT"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.twoge_config.metadata[0].name
                key  = "DB_PORT"
              }
            }
          }
          env {
            name = "DB_DATABASE"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.twoge_config.metadata[0].name
                key  = "DB_DATABASE"
              }
            }
          }
          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.twoge_secrets.metadata[0].name
                key  = "DB_USER"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.twoge_secrets.metadata[0].name
                key  = "DB_PASSWORD"
              }
            }
          }
        }
      }
    }
  }
}

# Create Twoge Service with LoadBalancer
resource "kubernetes_service" "twoge" {
  metadata {
    name      = "twoge-service"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }
  spec {
    selector = {
      app = "twoge"
    }
    port {
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }
    type = "LoadBalancer"
  }
}