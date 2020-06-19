# Volledige eindopstelling

In deze blogpost zal het design van de eindopstelling van deze stage besproken worden.

## Repo's

voor elke microservice zal er een repo voorzien worden. Deze repo’s bestaan uit puur de files nodig voor builds, testen en simpele deployments (deployment + service + ingress). Er zal ook een repo aanwezig zijn met alle andere manifesten nodig om de infrastructuur werkende te houden (tekton manifesten, istio manifesten, flagger manifesten).

## Devops werking

Als er development aan een service moet gebeuren zal via een nieuwe branch deze development gebeuren. Bij elke commit runned er een pipeline voor het CI gedeelte (test runnen, build de image?, report back). Wanneer men denkt klaar te zijn voor een nieuwe master versie wordt er een pull request gecreëerd. Deze zal dan een build pipeline starten voor een test deployment van deze applicatie en terug reporten (build succesvol, testen succesvol, ip om build te bereiken). Er zal ook gekeken worden naar de mogelijkheid om deze pull request te gebruiken om specifieke waarden mee te geven aan de pipeline (bv test ratio voor canary deployment)

Als deze pull request goed gekeurd wordt zal er een merge naar master gebeuren, waar opnieuw een build pipeline zal starten om uiteindelijk de main applicatie te herbouwen en deployen.

Voor de infra repo zal flux gebruikt worden om alle onderdelen van de git repo op de laatste versie te behouden, er is geen nood om voor manifesten een pipeline op te bouwen, deze moeten enkel geapplyed worden. Hiervoor kan een tool zoals flux zeer handig zijn.

## Infrastructuur

Voor de uiteindelijke applicatie zal gebruik gemaakt worden van Istio en flagger (voor canary deployments). Zoals eerder vermeld staan de manifesten om deze te configureren in een repo die gewatched wordt door flux. Als het nodig is kunnen we gebruik maken van git submodules om de istio, flagger en andere configs meer modulair te maken.

–einde?– 
