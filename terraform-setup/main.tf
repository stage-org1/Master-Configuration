provider "google" {
  credentials = file("credentials.json")
  project = "flowfactor"
  region = "europe-west1"
}


resource "google_container_cluster" "primary" {
  name = "${var.prefix}gkecluster-primary"
  location = var.zone
  initial_node_count = 3
  remove_default_node_pool = false


  master_auth {
    username = var.username
    password = var.password
  }

  node_config {
    preemptible = true
    machine_type = var.machine_type

    metadata = {
      "created-by" = var.creator
    }
  }
}

resource "google_container_node_pool" "workers" {
  name = "${var.prefix}gkenodepool-workers"
  location = var.zone

  cluster = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible = true
    machine_type = var.machine_type

    metadata = {
      "created-by" = var.creator
    }
  }
}


