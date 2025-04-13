provider "aws" {
  region = "us-east-1"
}

data "aws_eks_cluster" "cluster" {
  name = "twoge-mikhail-cluster2"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.cluster.name]
    command     = "aws"
  }
}

variable "image_tag" {
  description = "The tag of the Docker image to deploy"
  type        = string
}

variable "docker_username" {
  description = "Docker Hub username"
  type        = string
}

resource "kubernetes_namespace" "twoge_app" {
  metadata {
    name = "twoge-app"
    labels = {
      name = "twoge-app"
    }
  }
}

resource "kubernetes_config_map" "twoge_config" {
  metadata {
    name      = "twoge-config"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }

  data = {
    DB_HOST     = "postgres-service"
    DB_PORT     = "5432"
    DB_DATABASE = "twoge"
  }
}

resource "kubernetes_secret" "twoge_secrets" {
  metadata {
    name      = "twoge-secrets"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }

  data = {
    DB_USER     = "cG9zdGdyZXM="  # "postgres" in base64
    DB_PASSWORD = "cG9zdGdyZXM="  # "postgres" in base64
  }

  type = "Opaque"
}

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

resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = kubernetes_storage_class.gp3.metadata[0].name
  }
}

resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres-deployment"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
    labels = {
      app = "postgres"
    }
  }

  spec {
    replicas = 1
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
          image = "postgres:13"
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

resource "kubernetes_deployment" "twoge" {
  metadata {
    name      = "twoge-deployment"
    namespace = kubernetes_namespace.twoge_app.metadata[0].name
    labels = {
      app = "twoge"
    }
  }

  spec {
    replicas = 2
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