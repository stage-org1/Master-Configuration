# Jenkins X Installatie

De standaard installatie van jenkins x gebeurt via de jenkins x tool. Hier zijn constant veranderingen aan. Commands zoals Jx install zijn al als deprecated gemarked, de huidige laatste manier is door het gebruik van Jx Boot. Dit zal in deze blogpost doorlopen worden.

## Prereq's

jenkins x vermeld geen echte prerequirements, maar uit ervaring van de jenkins x installatie op te stellen zijn er zeker enkele prerequirements voor een vlotte installatie te kunnen doorlopen.

De belangrijkste is de mogelijkheid om loadbalancers aan te maken die publieke ip’s ontvangen. Dit zorgt ervoor dat setups op minikube sterk afgeraden worden. De reden dat deze loadbalancers aangemaakt moeten worden is omdat jx gebruik maakt van github webhooks. Dit zorgt er ook voor dat jenkins x niet eenvoudig op elk cloud platform kan geinstalleerd worden (uitgevonden door install test op digital ocean).

Buiten de mogelijkheid voor een loadbalancer op te stellen, moet er ook een ingress controller aanwezig zijn. Voor de veiligheid zou ik een standaard nginx ingress controller aanraden. Eerder heb ik problemen gehad met google’s default ingress controller (doet bepaalde alive checks en als deze false terug komen probeert de controller de routing zelfs niet uit te voeren en geeft zijn eigen 500 error). Maar jenkins x lijkt momenteel wel te werken met de default gke ingress controller.

Een laatste requirement zijn de resources die jenkins x nodig heeft om zichzelf op te starten. Deze worden niet gecontroleerd tijdens de installatie, en geven ook geen error als er te weinig resources aanwezig zouden zijn. Dit heb ik ontdekt na een installatie op mijn oorspronkelijke cluster (3 master nodes google compute 1-standard-1 en 1 worker node zelfde specs). Alles werkte, maar sommige pods wouden niet opstarten, na dieper te onderzoeken kwam dit door een tekort aan cpu resources. Daarna heb ik gekeken naar de jenkins x terraform module welke waarden zij gebruikten. Van wat ik kan opmerken gebruiken ze minimum 3 en maximum 5 1-standard-2 nodes. Na mijn opstelling up te graden via terraform werkte de installatie dus perfect.

Extra: er is de mogelijkheid om s3 buckets of dergelijke cloud storage oplossingen te linken aan je jenkins x installatie voor het saven van logs. Vele van deze settings kunnen gevonden worden in de default configuratie.

## Default configuratie

Zoals eerder vermeld was, gebruiken we jx boot. Jx boot maakt gebruik van configuratie files die aanwezig zijn in de directory waar jx boot gerunned wordt. Als er geen configuratie files aanwezig zijn, dan vraagt jx boot aan de user om deze te clonen. Dit is de gemakkelijkste en snelste manier om een basic default configuratie op te stellen. Voor mijn persoonlijke opstelling heb ik 1 aanpassing gedaan aan de default configuratie en die is een lijn in jx-requirements.yaml die toelaat om publieke github repo’s aan te maken in de plaats van private repo’s.

Daarna kan men de stappen van jx boot gewoon doorlopen. Enkele van de belangrijke stappen zijn: aanmaken van username en pass, github (bot) account linken (username + token), confirmatie van tls of geen tls webhooks.

De stappen zijn zeer eenvoudig, maar moest je vastkomen kan je altijd ? antwoorden en de uitleg krijgen. Voor de github token bv zal dit een link genereren om een token aan te maken met de correcte rechten.

Na het opstellen van de jx cluster is het misschien handig om ook de ui toe te voegen. dit kan gebeuren via de command “jx add app jx-app-ui”. Bij de default configuratie maakt dit een pull request aan in een van de 3 github repo’s die de jx install aanmaakt (dev repo). en door deze pull request te accepten start de pipeline om de ui app toe te voegen aan de cluster.

## Eerste vindingen Jenkins X

Jenkins x komt met een heel pak extra bagage. Na een lange installatie met vele stappen, had ik de mogelijkheid om applicaties toe te voegen. Dit doen ze door het gebruik van buildpacks. Als ik zo een buildpack bekijk dan proberen ze de oude manier van jenkins builds te behouden. Het concept achter een buildpack is dat alles voor je applicatie gegeven wordt, en dat de jx tool zelf zal herkennen welk soort applicatie je wilt creeeren. Zo komt een default node buildpack bv met een vooraf gegenereerde docker file, skaffold files, helm install file (met mogelijkheid voor gebruik flagger en Istio) en een tekton pipeline. Er zijn waarschijnlijk nog resources die hierbij komen die ik gemist heb, maar dit zijn de belangrijkste. Hoewel dit zeer aangenaam is, de dockerfile bepaald nu al hoe de applicatie eruit zal zien, en aanpassen is zeer gelimiteerd. Ik heb nog niet echt een manier gezien (dit zal volgende week verder onderzocht worden) om manueel gemakkelijk build packs aan te maken of aan te passen, maar de dockerfiles zijn ook niet echt geoptimaliseerd. Dit is natuurlijk ook zeer moeilijk te bereiken voor ELKE applicatie, en een perfecte dockerfile kan een applicatie veel helpen (minimaliseren image size, build steps).

Op het vlak van de pipelines is er ook iets zeer raar dat ik opgemerkt heb. Normaal gezien bestaan tekton pipelines uit tasks (collectie van steps) en pipelines (collectie van tasks). Een task kan failen als 1 van de steps failed, maar tasks kunnen async runnen. Tijdens mijn (vroege) testen van jenkins x lijkt deze enkel tasks te gebruiken. Het vult namelijk een task met allemaal steps (voor mijn default install 24 steps) wat extreem veel is. Later zal hier meer onderzoek naar gedaan worden, maar als ik een eerste gok moet wagen waarom dit is, is omdat ze geen build steps gebruiken in een dockerfile en deze errors opvangen vanuit kaniko, maar omdat ze manueel containers maken om hun testen uit te voeren (wat meer resources vraagt en trager is).

