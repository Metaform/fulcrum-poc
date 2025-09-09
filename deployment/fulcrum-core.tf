resource "kubernetes_namespace" "fulcrum-ns" {
  metadata {
    name = "fulcrum-core"
  }
}

resource "kubernetes_deployment" "fulcrum-core-postgres" {
  metadata {
    labels = {
      "io.kompose.service" : "postgres"
    }
    name      = "postgres"
    namespace = kubernetes_namespace.fulcrum-ns.metadata.0.name
  }
  spec {
    replicas = "1"
    selector {
      match_labels = {
        "io.kompose.service" : "postgres"
      }
    }
    template {
      metadata {
        labels = {
          "io.kompose.service" : "postgres"
        }
      }

      spec {
        container {
          name              = "postgres"
          image             = "postgres:17-alpine"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 5432
            protocol       = "TCP"
          }
          env {
            name  = "POSTGRES_DB"
            value = "fulcrum_db"
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = "fulcrum_password"
          }
          env {
            name  = "POSTGRES_USER"
            value = "fulcrum"
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "fulcrum", "-d", "fulcrum_db"]
            }
            failure_threshold = 5
            period_seconds    = 5
            timeout_seconds   = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    labels = {
      "io.kompose.service" : "postgres"
    }
    name      = "postgres"
    namespace = kubernetes_namespace.fulcrum-ns.metadata.0.name
  }

  spec {
    type = "NodePort"
    port {
      port        = 5432
      target_port = "5432"
    }
    selector = {
      "io.kompose.service" : "postgres"
    }
  }
}

resource "kubernetes_deployment" "fulcrum-core-api" {
  metadata {
    labels = {
      "app" : "core-api"
    }
    name      = "core-api"
    namespace = kubernetes_namespace.fulcrum-ns.metadata.0.name
  }
  spec {
    replicas = "1"
    selector {
      match_labels = {
        "app" : "core-api"
      }
    }
    template {
      metadata {
        labels = {
          "app" : "core-api"
        }
      }

      spec {
        restart_policy = "Always"
        image_pull_secrets {
          name = kubernetes_secret.ghcr-secret.metadata[0].name
        }
        container {
          name              = "core-api"
          image             = "ghcr.io/paullatzelsperger/fulcrum-core:latest"
          image_pull_policy = "Always"
          port {
            container_port = 3000
            protocol       = "TCP"
          }
          env {
            name  = "FULCRUM_DB_DSN"
            value = "host=postgres.fulcrum-core.svc.cluster.local user=fulcrum password=fulcrum_password dbname=fulcrum_db port=5432 sslmode=disable"
          }
          env {
            name  = "FULCRUM_METRIC_DB_DSN"
            value = "host=postgres.fulcrum-core.svc.cluster.local user=fulcrum password=fulcrum_password dbname=fulcrum_db port=5432 sslmode=disable"
          }
          env {
            name  = "FULCRUM_PORT"
            value = "3000"
          }
          env {
            name  = "FULCRUM_HEALTH_PORT"
            value = "3001"
          }
          env {
            name  = "FULCRUM_AUTHENTICATORS"
            value = "token" # no oauth needed here
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "fulcrum-core-api-service" {
  metadata {
    labels = {
      app = "core-api"
    }
    name      = "core-api-lb"
    namespace = kubernetes_namespace.fulcrum-ns.metadata.0.name
  }

  spec {
    type = "LoadBalancer"
    port {
      port        = 3000
      target_port = "3000"
    }
    selector = {
      app : "core-api"
    }
  }
}
