# Istio vs Consul vs Linkerd

Service meshes zijn een soort van vervanging van de standaart kubernetes container networking. Dit is de beste manier die ik kan vinden om service meshes uit te leggen aan iemand die er geen ervaring mee heeft.

De specifieke werking uitleggen van “een service mesh” is zeer moeilijk omdat ze allemaal anders werken.

Istio en linkerd werken op een vergelijkbare manier, door proxy containers te injecten naast bestaande containers en die proxy containers gebruiken om de routing behandelen.

Consul daarin tegen werkt zeer anders, door een centrale server in de cluster te zetten die zelf de routing doet behaald deze provider hetzelfde resultaat.

En moesten er nog populaire alternatieven opkomen kunnen ook zij op een andere manier werken in de cluster. Er is dus geen vaste definitie voor een service mesh op het technische vlak. Wat deze providers wel allemaal gelijk maakt is het feit dat ze bepaalde functionaliteit toevoegen die niet standaard behaald kan worden met de resource types die met een standaard kubernetescluster komen.

Deze service meshes laten operaties toe zoals advanced http, tcp en https routing, traffic encryptie, metrics opnemen van de traffic in de cluster, etc. En aangezien ze dit allemaal op een andere manier doen heb ik het eerste deel van mijn stage mij bezig gehouden met deze 3 providers te bestuderen.

Ik zoek vooral naar 2 aspecten wanneer ik service meshes bekijk: bruikbaarheid en functionaliteit.

Het kubernetes model heeft het zeer gemakkelijk gemaakt voor developers om een inzicht te krijgen op de infrastructuur van hun applicatie, en de barrière om zelf een infrastructuur voor een applicatie op te zetten verlaagt. Deze kwaliteit is dus in mijn ogen een groot probleem

Daartegenover staat wel functionaliteit. Het nut van een service mesh moet er nog altijd zijn. En dit kan in verschillende mate zoals we zullen zien, sommige providers geven veel opties aan hun gebruikers, en andere minder.

## Istio

Istio is een service mesh die veel mogelijkheden bied, gebundeld komt met een groot aantal dashboards om metrics op te nemen en nog altijd redelijk kubernetes native blijft.

Installatie van Istio is zeer eenvoudig en kan op meerdere manieren. Via helm (hoewel dit afgeraden is) of via de cli tool (istioctl). De cli tool genereerd kubernetes manifesten die je dan kan apply’en op de cluster of manueel kan aanpassen. Het laat ook toe om enkele profiles te selecteren, bv het demo profiel komt met zo veel mogelijk dashboards en tools om metrics te verzamelen van je cluster, en het default profile is een goede base om op te starten als je je cluster niet wilt overbelasten met onnodige dashboards.

De routing in istio gebeurt zoals eerder besproken via pods/containers die geinject worden in de deployments en de routing voor die containers behandeld. Deze injectie kan manueel gebeuren via de cli tool of door een label te zetten op bv een namespace en zo worden alle items in die namespace die geinject kunnen worden geinject.

Om eigenlijke acties uit te voeren zoals traffic splitten tussen meerdere services wordt er gebruik gemaakt van een pak nieuwe resources. Hieronder enkel van de meest gebruikte:

De virtual service resource kan gebruikt worden om een groep services samen te brengen en basic requests aan die virtual service te routen naar echte kubernetes services. Gateways laten het toe om services te exposen of traffic op te vangen van een bepaalde service. Destination rules geven developers traffic policy regels op de traffic die doorheen hun cluster gaat.

Tenslotte komt Istio ook met zijn eigen ingress gateway, dit betekend dat we dezelfde routing rules kunnen gebruiken voor onze ingresses en deze niet manueel moeten instellen.

## Consul

Zoals eerder vermeld gebruikt consul 1 deployment in de cluster, waar alle requests naartoe gestuurd zullen worden, deze deployment is dan verantwoordelijk voor de routing in de cluster.

Het opzetten van consul is niet zo simpel als die van Istio of linkerd. De standaart installatie gebeurt via helm, in plaats van de command tool, maar is redelijk eenvoudig. Nadat we de manifesten op de cluster uitvoeren, moeten we onze interne dns in de cluster (kube-dns of core-dns) aanpassen zodat deze requests doorstuurt naar de consul deployment. Dit betekend ook dat vanuit zichzelf er een andere naming convention is voor services. Als je als developer bv vroeger de backend service kon bereiken via de naam http://backend-service dan wordt deze nu aangepast naar http://backend-service.service.consul. Dit kan aangepast worden maar moet ook opnieuw manueel geconfigureerd worden.

Om eigenlijke consul objecten/resources te configureeren gebruikt consul zijn eigen objecten die je dan stuurt naar de consul service via de consul command line tool. Het probleem hiermee is, is dat deze niet uit zichzelf geexposed kan worden, dus moet je eerst een kubectl port-forward uitvoeren, en daarna kan je de command line tool gebruiken. Het is dus best om hier een alias voor te maken (bv consul-init). Nadat de consul service bereikbaar gemaakt is kun je gebruik maken van manifesten geschreven in HCL of json om objecten te configureren.

De syntax/werkwijze van Consul is ook zeer anders dan Istio en Linkerd. Hieronder een voorbeeld configuratie van traffic splitting tussen 2 services.

Stel dat we momenteel een frontend service hebben die contact maakt met een backend service en we willen dat 50% van de traffic naar een tweede versie van de backend service gaat. In tegenstelling tot Istio kunnen we niet zomaar een label toevoegen aan elke deployment in de backend service group en zo subsets maken van de service. Subsets van een service bestaan wel, maar deze gaan dan over consul services. Een service in consul is een compleet ander item, en consul neemt de kubernetes services niet over in zijn eigen services. Consul zal een lijst opmaken van deployments die momenteel runnen in de cluster, en zelf een service voor elke deployment aanmaken. Je kan ook manueel een service aanmaken voor een deployment, maar deze dan eigenlijk kunnen laten wijzen naar de correcte deployment is ook zeer moeilijk te doen (selectors gaan niet af van labels, maar van annotations met de correcte labeling).

Dus onze deployments hebben al services, maar deze zijn nog niet correct geconfigureerd. Dit kan automatisch gebeuren door gebruik van annotations met de correcte syntax, maar wat vaker gedaan wordt is de consul cli tool gebruiken om service-default objecten te applyen op de services. Een voorbeeld van zo een service-default object:

```
{
  "kind": "service-defaults",
  "name": "backend-deployment-v1",
  "protocol": "http"
}
```

Dit zet het default protocol van de service “backend-deployment-v1” (een naam die automatisch gegenereerd wordt afhankelijk van de titel van de deployment). Dit moet namelijk omdat het protocol tcp niet zomaar traffic-shifting toelaat in consul’s equivalent van een traffic splitter. We moeten deze defaults instellen voor elke service die we aanmaken/gebruiken. Daarna moeten we nog een hoofd service hebben die de frontend zal callen, we zullen deze backend-service noemen (volledige url is dan backend-service.service.consul). Let op deze worden op een andere manier geconfigureerd in de cluster. In tegenstelling tot service-defaults die we “applyen” op de cluster, worden services zelf geregistered. Dus we creëren een configuratie file voor de service die we dan via de register command in de cluster steken.

```
{
"service":
  {
   "name": "backend-service",
   "protocol": "http"
   "port": 80
  }
}
```

We zouden voor deze service ook service defaults kunnen configureren, maar in dit geval hebben we het protocol al ingesteld bij het aanmaken van de service. Tenslotte hebben we een service-splitter nodig:

```
{
  "kind": "service-splitter",
  "name": "backend-service",
  "splits": [
    {
      "weight": 50,
      "service": "backend-deployment-v1" 
    },
    {
      "weight": 50,
      "service": "backend-deployment-v2" 
    }
  ]
}
```

De name van de service-splitter is belangrijk, want deze moet gelinked kunnen worden aan de service die de oorspronkelijke requests ontvangt. Als we subsets willen gebruiken van een service (opnieuw moeilijk om te configureren van kubernetes af) dan moeten we ook nog gebruik maken van een service-resolver:

```
{
  "kind": "service-resolver",
  "name": "backend-service",
  "subsets": {
    "v1": {
      "filter": "Service.Meta.version == 1"
    },
    "v2": {
      "filter": "Service.Meta.version == 2"
    }
  }
}


{
  "kind": "service-splitter",
  "name": "backend-service",
  "splits": [
    {
      "weight": 50,
      "service_subset": "v1"
    },
    {
      "weight": 50,
      "service_subset": "v2" 
    }
  ]
}
```
We kunnen deze version tags ook zetten in de service-defaults files, maar dit is opnieuw nog een stap configuratie, zonder veel voordeel (de services van de deployments worden nog altijd uit zichzelf geconfigureerd). 

## Linkerd

Linkerd werkt bijna volledig op dezelfde manier dat Istio werkt. Ze gebruiken ook envoy proxies om zo hun routing te configureren.

Het verschil met Istio is in de gebruiksvriendelijkheid en het aantal features. Er is veel meer controle over wat er met http packets moet gebeuren op vlak van routing, monitoring etc dan er is in linkerd.

In tegenstelling tot Istio kan linkerd gebruik maken van Kubernetes native services om hun routing op te bepalen. Dit maakt linkerd een pak gebruikt vriendelijker, omdat we geen services moeten verbinden met virtual services om die daarna nog eens te verbinden met andere virtual services.

We kunnen gewoon gebruik maken van de bestaande infrastructuur en applicaties hieraan toevoegen. Als voorbeeld nemen we opnieuw het concept van blue-green deployments.

Er is een applicatie aanwezig die bestaat uit 2 microservices, 1 microservice (frontend-service) legt contact met een andere microservice (backend-service) en returned de tweede microservice’s response. We willen hier een tweede versie van de backend-service toevoegen.

Door een derde microservice aan te maken en deze een Kubernetes service met de naam backend-service-v2 te geven kunnen we dit traffic-split manifest gebruiken om de traffic 50% te routen naar de oude service en 50% naar de nieuwe:

```
apiVersion: split.smi-spec.io/v1alpha1
kind: TrafficSplit
metadata:
  name: traffic-split-v3
spec:
  service: backend-service
  backends:
  - service: backend-service
    weight: 500m
  - service: backend-service-v2
    weight: 500m
```

De opstelling hiervan is dus redelijk simpel en kan makkelijk geïnstalleerd worden bovenop een bestaande app. Het probleem hiermee is dat dit bijna alles is wat je met de default installatie van linkerd kunt doen. Items zoals routing via headers, etc, komen niet standaard geïnstalleerd. De functionaliteit om projecten zoals Flagger te gebruiken zijn nog altijd mogelijk. (NOG UIT TE BREIDEN)











