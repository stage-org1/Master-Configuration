# Consul service mesh

Consul is een andere service mesh, gecreëerd door hashicorp, en werkt net zoals istio ook op alternatieven van kubernetes. Het is vooral gedesigned om te werken op nomad, en gebruikt daarom ook een andere tool om zijn eigen configuratie te doen, in tegenstelling tot istio’s kubernetes resource types. 

## Installatie

De consul installatie, net zoals meeste extensies/addons op een kubernetes cluster is redelijk gemakkelijk. Het maakt gebruik van een helm chart om de installatie uit te voeren. Dit waren mijn configuratie opties:

```
# Choose an optional name for the datacenter
global:
  datacenter: minikube

# Enable the Consul Web UI via a NodePort
ui:
  service:
    type: 'NodePort'

# Enable Connect for secure communication between nodes
connectInject:
  enabled: true
  k8sAllowNamespaces: ["*"] #allow injection in all namespaces
  k8sDenyNamespaces: []

client:
  enabled: true

# Use only one Consul server for local development
server:
  replicas: 1
  bootstrapExpect: 1
  disruptionBudget:
    enabled: true
    maxUnavailable: 0
```

## Deployment

De standaart deployment is een variatie van onze oude deployments:

```
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-a
  # namespace: consul-project-1
  annotations:
    "consul.hashicorp.com/connect-inject": "true" #dit is hoe consul injection handled
spec:
  replicas: 1
  selector:
    matchLabels:
      server: "http"
      app: "project-1"
      expose: "true"
  template:
    metadata:
      labels:
        server: "http"
        app: "project-1"
        expose: "true"
      annotations:
        "consul.hashicorp.com/connect-inject": "true"
    spec:
      containers:
        - name: server-a
          image: beppev/server-a:master-consul
          imagePullPolicy: "Always"
          ports:
            - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-b
  # namespace: consul-project-1
  annotations:
    "consul.hashicorp.com/connect-inject": "true" #dit is hoe consul injection handled
spec: 
  replicas: 1
  selector:
    matchLabels:
      server: "http"
      app: "project-1"
      version: v1
      backend: "true"
  template:
    metadata:
      labels:
        server: "http"
        app: "project-1"
        version: v1
        backend: "true"
      annotations:
        "consul.hashicorp.com/connect-inject": "true"
    spec:
      containers:
        - name: server-b
          image: beppev/server-b:master-consul
          imagePullPolicy: "Always"
          ports:
            - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-b-test
  # namespace: consul-project-1
  annotations:
    "consul.hashicorp.com/connect-inject": "true" #dit is hoe consul injection handled
spec:
  replicas: 1
  selector:
    matchLabels:
      server: "http"
      app: "project-1"
      version: v2
      backend: "true"
  template:
    metadata:
      labels:
        server: "http"
        app: "project-1"
        version: v2
        backend: "true"
      annotations:
        "consul.hashicorp.com/connect-inject": "true" #dit is hoe consul injection handled
    spec:
      containers:
        - name: server-b-test
          image: beppev/server-b:experimental-consul
          imagePullPolicy: "Always"
          ports:
            - containerPort: 80
```
Omdat consul een andere tool gebruikt ter vervanging van services, zijn deze dus niet aangemaakt in de kubernetes cluster, en zullen deze op de consul server (die als pod in de cluster draait) geconfigureerd worden.

## Server-check Service

Dit is de service die we zullen gebruiken om traffic te shiften tussen de server-b en server-b-test “services”. Hoewel we geen services aangemaakt hebben voor deze servers, wordt op de hashicorp server ook resources aangemaakt die in die server “services” noemen. Om verwarring te vermijden in deze write-up zal ik naar deze services verwijzen als consul-services. Hieronder de json file die we kunnen gebruiken om een consul-service aan te maken:

```
{
	"service": {
		"name": "server-check"
    "protocol": "http"
	}
}
```
 Zoals we hier kunnen zien zijn er maar 2 items aanwezig, de consul-service naam en het protocol. Eerder konden we deze waarschijnlijk ook configureren via annotations op onze deployments, maar de syntax hiervoor zou dan niet gedocumenteerd zijn. Voor deze reden moeten we “service-defaults” configureren voor onze andere services. in HCL syntax:
 
```
Kind = "service-defaults"
Name = "server-b"
Protocol = "http"
```

De name hier bepaald welke consul-service geconfigureerd zal worden.

Ten slotte moeten we nog onze eigenlijke traffic splitter configureren (opnieuw in HCL syntax):

```
kind = "service-splitter"
name = "server-check"
splits = [
  {
    weight         = 50
    service				 = "server-b"
  },
  {
    weight         = 50
    service				 = "server-b-test"
  },
]
```

Name verwijst opnieuw naar een bestande consul-service (anders worden de dns namen hiervoor niet aangemaakt, meer over dns later) en via het splits onderdeel kunnen we de traffic splitten tussen de twee consul-services. Je kan dit ook doen via sub-sets, maar aangezien we met deployments werken werden deze consul-services al voor ons aangemaakt.

## Consul resources aanmaken via de consul cli tool

Om deze resources eigenlijk te kunnen aanmaken moeten we eerst connectie kunnen maken met de consul-server buiten de webui, dit kunnen we doen door gebruik van de kubectl port-forward command te gebruiken: “kubectl port-forward hashicorp-consul-server-0 8500:8500”. Uit persoonlijke ervaring ga je deze command vaak gebruiken als je consul services aanmaakt, dus het is de moeite waard om hiervan een alias te maken. Om een nieuwe consul-service aan te maken gebruiken we de command consul service register:

```
consul services register consul/server-check-service.hcl
```

om consul-services te verwijderen kunnen we consul services deregister gebruiken met de consul-service naam of de config file die gebruikt werd om hem aan te maken.

Om de config files te applyen op de cluster gebruiken we de consul config write command:

```
consul config write consul/server-check-splitter.hcl
```

Natuurlijk moet eerst elke service-default file geapplied worden voordat men de splitter zelf kan applyen (service-splitter werkt enkel met consul-services die het http protocol gebruiken)

## Opstellen dns configuratie

Jammer genoeg configureerd consul zichzelf niet volledig doorheen de helm installatie, en we kunnen geen requests naar de services maken tot we de dns instellingen van kube-dns en/of core-dns aanpassen. De eerste stap hiervoor is de cluster-ip vinden van de consul-dns server.

```
get svc hashicorp-consul-dns
```

Dit geeft ons het cluster ip van de hashicorp-consul-dns service. We gaan deze dan gebruiken om kube-dns en/of core-dns te configureren:

## Kube-dns

Voor kube-dns te configureren hebben we een config map nodig:

```
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
  name: kube-dns
  namespace: kube-system
data:
  stubDomains: |
    {"consul": ["10.103.17.72"]}
```

Apply deze op de cluster en herstart de kube-dns pods (door ze te deleten ze herstarten automatisch).

## Core-DNS

Voor coredns editen we een config-map genaamd coredns in de namespace kube-system:

```
kubectl edit cm coredns -n kube-system
```

Door een veld toe te voegen kunnen we requests voor consul resolven naar de consul-dns service:

```
1 # Please edit the object below. Lines beginning with a '#' will be ignored,
  2 # and an empty file will abort the edit. If an error occurs while saving this file will be
  3 # reopened with the relevant failures.
  4 #
  5 apiVersion: v1
  6 data:
  7   Corefile: |
  8     .:53 {
  9         errors
 10         health {
 11            lameduck 5s
 12         }
 13         ready
 14         kubernetes cluster.local in-addr.arpa ip6.arpa {
 15            pods insecure
 16            fallthrough in-addr.arpa ip6.arpa
 17            ttl 30
 18         }
 19         prometheus :9153
 20         forward . /etc/resolv.conf
 21         cache 30
 22         reload
 23         loadbalance
 24     }
 25     consul { #TOEGEVOEGD VELD
 26         errors
 27         cache 30
 28         forward . 10.103.17.72 #CLUSTER IP CONSUL DNS SERVICE
 29     }
 30 kind: ConfigMap
 31 metadata:
 32   creationTimestamp: "2020-03-10T12:00:57Z"
 33   name: coredns
 34   namespace: kube-system
 35   resourceVersion: "30747"
 36   selfLink: /api/v1/namespaces/kube-system/configmaps/coredns
 37   uid: 48046d4d-41ec-4387-b97f-40442dc342e1
```

Hierna start je opnieuw de pods van core-dns door ze te deleten.

## Implementatie in Code

Om deze consul-services eigenlijk te contacteren moet men zijn requests routen naar SERVICENAAM.service.consul. Dit betekend dat alle vorige applicaties aangepast werden om dit te laten werken. Er is wel de mogelijkheid om ook automatisch kubernetes services aan te maken voor elke consul-service die aangemaakt wordt, maar dan moet men nog altijd de dns configuratie uitvoeren.

Het exposen van onze applicatie gebeurt nog altijd met een gewone kubernetes nodeport-service/loadbalancer.

