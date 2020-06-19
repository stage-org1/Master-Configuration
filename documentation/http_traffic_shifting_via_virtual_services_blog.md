# Http Traffic Shifting via virtual services

## Service Meshes

Service meshes zijn een extensie boven op kubernetes (zoals tekton pipelines) die ons meer controle geven over onze deployments, pods, etc. Een van deze mogelijkheden is traffic routing. Dit houd bv in dat we traffic 50% van de tijd naar 1 deployment zullen sturen en een andere 50% naar een andere. In deze blogpost zal besproken worden hoe dit geimplementeerd wordt op istio (een service mesh provider)

## Istio installatie

Istio is een service mesh provider die makkelijk te installeren valt op een kubernetes cluster, daarboven op is het ook de meest populaire service mesh provider. Standaard komt istio met enkele vooraf geïnstalleerde tools (bv, kiali, …) maar deze kunnen ook achteraf manueel geïnstalleerd worden. Momenteel zullen we maar 1 van deze tools gebruiken, kiali.

Installatie van istio is redelijk gemakkelijk. Alles gebeurt via een cli tool istiocli. Om de meest barebones versie van istio te installeren runned men 

```
istioctl manifest apply
```

Dit betekend wel dat als we alle tools erboven op willen dat we deze manueel moeten installeren. Men kan dit doen door eerst het barebones manifest en het gewenste manifest die de plugins heeft te genereren:

```
istioctl manifest generate > default.yaml
istioctl manifest generate --set profile=demo > demo.yaml
```

en daarna de verschillen te vergelijken. Men kan ook manueel de installatie runnen vb (kiali install):

```
bash <(curl -L https://git.io/getLatestKialiOperator) --accessible-namespaces '**'
```

Je kan ook de helm installatie van istio gebruiken om hier bepaalde tools niet te laten installeren.

Voor dit project zullen we het demo profile gebruiken zodat we gebruik kunnen maken van alle tools om onze applicatie te monitoren.

## Onze Base Applicatie

De base applicatie wordt voortgebouwd op de eerdere applicatie die gecreëerd was, maar we maken een 2e versie van serverB aan die exact hetzelfde doet maar de naam serverC heeft en in deze response meegeeft

```
{
  "serverName": "serverC", 
  "success": "true"
}
```

Zo kunnen we elk onderdeel van de applicatie testen: extern bereik server a, interne communicatie server a > b, interne communicatie server a > c, interne traffic routing a > b/c

## Manifesten

Normaal gezien om onze applicatie sidecars te geven (dit zijn toevoegingen aan pod die ons de mogelijkheid geven om te monitoren) moeten we deze injecten via het istioctl command:

```
istioctl kube-inject -f deploy.yaml > deploy.istio.yaml
```

Door gebruik van namespaces kunnen we istio de sidecar automatisch laten injecten. Dit maakt ook cleanup makkelijker later omdat we gewoon alle resources met de namespace + de namespace kunnen verwijderen.

## Namespaces

Om istio de sidecars automatisch te laten injecten moeten we eerst ervoor zorgen dat istio die mogelijkheid heeft. Bij meeste clusters is dit standaard al toegelaten, maar moest dit niet het geval zijn is dit waarschijnlijk omdat admission controllers niet enabled zijn in de kubernetes cluster.

Als dit niet het geval is kunnen we gemakkelijk sidecar injection enablen via een label toe te voegen aan de namespace:

```
apiVersion: v1
kind: Namespace
metadata:
  name: istio-project-1
  labels:
    istio-injection: enabled
```

## Deployment & Services

Hier hebben we de oude pods die we gebruikten omgezet naar deployments (met maar 1 replica) en een laatste deployment (server-c) toegevoegd:

```
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-a
  namespace: istio-project-1
spec:
  replicas: 1
  selector:
    matchLabels:
      server: "http"
      app: "project-1" #app label bepaald groepering pods in kiali dashboard dus makkelijker te gebruiken
      expose: "true"
  template:
    metadata:
      labels:
        server: "http"
        app: "project-1"
        expose: "true"
    spec:
      containers:
        - name: front-end
          image: beppev/server-a:latest
          ports:
            - containerPort: 5000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-b
  namespace: istio-project-1
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
    spec:
      containers:
        - name: front-end
          image: beppev/server-b:latest
          ports:
            - containerPort: 6000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-c
  namespace: istio-project-1
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
    spec:
      containers:
        - name: front-end
          image: beppev/server-c:latest
          ports:
            - containerPort: 6000
```

Men kan ook zien dat er enkele labels bijgekomen zijn. Het app label helpt bepaalde tools om resources te groeperen per project, maar belangrijker, het version label is wat we zullen gebruiken om onze traffic te shiften.

Op het vlak van services zijn deze redelijk gelijk gebleven

```
apiVersion: v1
kind: Service
metadata:
  name: server-check
  namespace: istio-project-1
  labels:
    app: "project-1"
spec:
  selector:
    backend: "true"
  ports:
    - name: http
      protocol: TCP
      port: 6000
```

de backend: true label zorgt dat we een service hebben met deployments b en c, die we later kunnen aanspreken via een virtual service.

Momenteel is er ook nog een loadbalancer service die server-a exposed maar deze zal later vervangen worden door de gateway die istio zelf opzet.

## Destination rule

Dit is onze regel die bepaald hoe we onze traffic routen.

```
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: server-check-destination
  namespace: istio-project-1
  labels:
    app: "project-1"
spec:
  host: server-check
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

Via deze regel bepalen we dat er 2 subsets zijn in de host(server-check) service (version v1 en version v2) en die kunnen we later gebruiken om de traffic te shiften.

## Gateway

Dit is de gateway die gebruik wordt om onze traffic te routen

```
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: server-check-gateway
  namespace: istio-project-1
  labels:
    app: "project-1"
spec:
  selector:
    expose: "true"
  servers:
    - port:
        number: 6000
        name: http
        protocol: HTTP
      hosts:
        - "*"
```

## Virtual Service

Dit is het belangrijkste onderdeel, het bepaald welke traffic naar waar geroute moet worden. 

```
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: server-check-service
  namespace: istio-project-1
  labels:
    app: "project-1"
spec:
  hosts:
    - "*"
  gateways:
    - server-check-gateway
  tcp:
  - match:
    - port: 6000
    route:
    - destination:
        host: server-check
        port:
          number: 6000
        subset: v1
      weight: 50
    - destination:
        host: server-check
        port:
          number: 6000
        subset: v2
      weight: 50
```

Tussen alle traffic die op de gateway toekomt met destination server-check stuur 50% naar version 1 en 50% naar version 2. Het uiteindelijk resultaat kan gevonden worden op 

## Expose via Istio ingress gateway

Om aan onze app te geraken kunnen we gebruik maken van de ingebouwde istio ingress gateway en virtual services voor de routing.

Er moet eerst een gateway aanwezigzijn die requests ontvangt via de ingress gateway

```
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: expose-server-gateway
  namespace: istio-project-1
  labels:
    app: "project-1"
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*"   
```

We kunnen dit specifyen via de selector (istio: ingressgateway)

Daarna hebben we de service nodig die gelinked zal worden aan onze frontend:

```
apiVersion: v1
kind: Service
metadata:
  name: expose-server-service
  namespace: istio-project-1
  labels:
    app: "project-1"
spec:
  ports:
    - name: http
      port: 5000
      protocol: TCP
  selector:
    expose: "true"
```

en ten slotte de virtual service die de routing zal beheren:

```
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: expose-server-vservice
  namespace: istio-project-1
  labels:
    app: "project-1"
spec:
  hosts:
    - "*"
  gateways:
    - expose-server-gateway
  http:
    - match: 
      - uri:
          prefix: /server-a
      route:
        - destination:
            port: 
              number: 5000
            host: expose-server-service
```




