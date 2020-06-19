# Kubernetes HA Cluster op cloud omgeving via terraform

Oorspronkelijk ging dit gebeuren op IBM’s cloud omgeving maar voor redenen (momenteel is IBM bezig met een herstructurering van hun cloud omgeving en documentatie is niet volledig & up to date) werd er de keuze gemaakt voor google’s cloud omgeving.

Om de google provider in terraform te laten werken hebben we een json file met de credentials nodig van een user met enkele rollen (waaronder iam service user). Hieronder het terraform script

```
variable "region" {
}

variable "project" {
}

variable "name" {
}

provider "google" {
  credentials = file("creds.json")
  project     = var.project
  region      = var.region
}


resource "google_container_cluster" "primary" {
  name     = "${var.name}cluster-primary"
  location = "${var.region}1-b"

  initial_node_count       = 3

  node_config {
    labels = {
      "node-role.kubernetes.io/master" = "master"
    }
  }
  master_auth {
    username = "beppe"
    password = "Azerty123456789!"

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "workernodes" {
  name       = "${var.name}nodepool-workernodes"
  location   = "${var.region}1-b"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "n1-standard-1"
    labels = {
      "node-role.kubernetes.io/worker" = "worker"
    }
    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}
```


Om de kubernetes nodes een role te geven kan er gebuik gemaakt worden door tags. Bv:

Master: “node-role.kubernetes.io/master” = “master”

Worker: “node-role.kubernetes.io/worker” = “worker”

De loadbalancer zit standaard al ingebouwd in google’s kubernetes api.

*UPDATE*

Google cloud zet de poorten die NodePort kan gebruiken om een service te exposen niet open, dit moet manueel met dit commando

```
gcloud compute firewall-rules create test-node-port --allow tcp:POORT
```
