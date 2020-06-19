# Verbetering CI gedeelte

Aan het begin van de week zijn er aanpassingen geweest aan de pipeline, en tijdens deze aanpassingen heb ik opgemerkt dat, hoewel ik het continuous delivery van mijn pipeline volledig afgewerkt heb, moet ik misschien een beetje meer focussen op het CI gedeelte van de pipeline.

Natuurlijk tot nu toe had ik dit nog niet opgemerkt want het enige dat er kon mislopen was een docker build (ik gebruikte enkel python en dockerfiles tot nu toe). Sinds het begin deze week heb ik een tocht ondernomen om de pipeline die ik gecreëerd had te zoveel mogelijk te optimaliseren, dit zal waarschijnlijk de meest onduidelijke blogpost tot nu toe zijn, en zal waarschijnlijk nog aangepast worden voor duidelijkheid. Maar ik wil deze ideeën toch ergens opschrijven zodat ik ze zeker niet uit het oog verlies.

## Tekton vs meer conventionele pipelines

Tekton in tegenstelling tot veel andere pipelines is is dat tekton zeer modulair is. Bijna elke resource in tekton is gedesigned om hergebruikt te worden in de verschillende stappen. Dit betekend dat mijn oorspronkelijk idee dit was:

1 pipeline voor 4 applicaties die 4 applicaties deployen.

Dit is een geweldig systeem moest tekton verder in zijn lifespan zijn. Momenteel zijn er geen native error logging capaciteiten, dus bv een gradle build die testen uitvoert en de test die faalt terug geven aan de developer is iets wat native niet mogelijk is in tekton. Er is nog geen on fail optie in de pipeline tasks (als een task faalt, en een latere stap depend op deze task faalt de volledige pipeline), hetzelfde geld ook voor manieren om output van tasks terug te reporten. Dus dit moet allemaal manueel gemaakt worden in containers. (later hier meer over).

## Design change 1: conditional pipelines

De eerste dagen van de week waren gespendeert te denken over andere manieren om deze infrastructuur te laten werken. Het oorspronkelijke idee was om nog 1 pipeline te gebruiken, en in het begin van de pipeline te bepalen welke soort build er moest gebeuren (gradle, dockerfile, etc). En daarna als deze lukt door te gaan naar de applicatie eigenlijk te deployen. Jammer genoeg (zoals eerder gezegd) kan de pipeline niet doorgaan als een task waar een andere task op depend niet kan uitgevoerd worden. De optie die dan wel mogelijk is is om scripten te maken per container en de errors via bash scripting op te vangen en op te slaan in results. Daarna kan op de deploy taak een conditional ingesteld worden om naar de output te kijken en te bepalen of de deployment moet gebeuren.

Het probleem hiermee is dat deze pipelines extreem lang kunnen duren (2u+). Dit komt omdat elke container moet checken of hij de correcte container is voor de build te laten gebeuren (golang build container start, kijkt of het een golang repo is, zo neen sluit terug af, door naar volgende container etc). De oplossing hiervoor zou conditionals zijn, en in de gitclone bepalen welke buildtype de correcte is. Dit kan jammer genoeg ook niet want conditionals zetten een task op failed, dus de conditionals zouden de volledige pipeline laten breken (deploy task moet nog altijd dependen op alle voorgaande buildtasks anders begint deze onmiddelijk voordat de container image zelfs aanwezig is op de image registry).

## Design change 2: meer pipelines

Aangezien een conditional pipeline niet echt een optie is, moeten we een andere optie bekijken. Pipelines voor elke repo. Oorspronkelijk was het idee om 1 event listener te hebben, en afhankelijk van de webhook te bepalen welke pipeline gerunned zou moeten worden. In tekton is dit geen optie, dus er moeten 4 event listeners aangemaakt worden elk met een pipeline. Het probleem hiermee is de performance. Dit maakte mijn cluster zo onstabiel dat ik zou wakker worden met logs van een pod die 500+ keren geherstart is tijdens de nacht. Daarboven op is het een zeer inefficiënte en anti-tekton/anti-kubernetes manier om te werken.

## Design change 3: pipelines in pipelines

Deze realisatie heeft enkele dagen geduurd, maar ik ben uiteindelijk op een realisatie gekomen:

Dockerfiles zijn kleine pipelines.

Dit betekend dat we mini pipelines kunnen embedden in elke git repo en we moeten gewoon de output van deze pipelines catchen en als status updates zetten op bv een github commit of een slack channel. (in ons geval updates op een github commit).

voor onze kaniko image gebruiken we nu de debug build (hoewel dit niet aangeraden is voor production (((dit is geen production environment ¯\_(ツ)_/¯)))). De reden dat we dit moeten doen is omdat de standaard kaniko image geen shell heeft en we kunnen daarom ook geen script creëren om de errors op te vangen en te schrijven naar de results.

Dit is wel nog altijd trager dan de conditional pipeline manier (build steps in een dockerfile zijn trager omdat kaniko een zeer trage manier is om docker files te builden, maar het is momenteel onze enige realistische optie) maar het is het beste wat we momenteel kunnen gebruiken.

Na een stap afgewerkt is kunnen we een synchronous task runnen met de volgende stap om een github status update te runnen, deze kunnen ook synchronous runnen met nog andere stappen. Nadat dit gebeurt is gebruiken we een conditional om de volgende stappen te laten falen door gebruik te maken met de results variables van de vorige stap.

## conclusie

⋅⋅*tekton pipelines is een jong project, maar door de natuur van containers, kunnen we altijd manueel de onderdelen die deze addon mist zelf creëren.
⋅⋅*containers pullen, starten en destroyen duurt lang
⋅⋅*node performance is een belangrijk deel van het designen van een pipeline
⋅⋅*dockerfiles zijn zeer krachtig
⋅⋅*en vergeet niet voor wie je een pipeline (of gelijk wel product) ontwikkeld (voor de developers die ze moeten gebruiken, niet voor jezelf)
