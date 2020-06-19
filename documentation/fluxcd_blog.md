# Fluxcd

Fluxcd is een tool/pod/deployment die je kan installeren op je cluster. Wat de tool eigenlijk doet is elke x (standaart 5) minuten je meegegeven git repo clonen/pullen en dan bepaalde manifesten applyen op je cluster.

## Installatie

Installatie van fluxcd is zeer gemakkelijk, en kan gedaan worden via helm of via fluxctl. Al dat er moet gebeuren is onderstaande fluxctl command in voeren en daarna flux’s ssh key toevoegen aan je repo/account zodat de client toegang heeft om de repo te clonen

```
export GHUSER="YOURUSER"
fluxctl install \
--git-user=${GHUSER} \
--git-email=${GHUSER}@users.noreply.github.com \
--git-url=git@github.com:${GHUSER}/flux-get-started \
--git-path=namespaces,workloads \
--namespace=flux | kubectl apply -f -
```

## Implementatie

Fluxcd apply’ed dus elke 5 minuten je manifesten in de repo die je meegeeft op de cluster. Dit is zeer handig voor kleine applicaties die al een lokale pipeline zouden hebben (fluxcd biedt namelijk geen ci capaciteiten) die de pod images build en pushed naar een container registry.

## Verbeteringen

Het eerste idee dat bij mij opkwam om dit te verbeteren was door gebruik te maken van tekton een volledige ci/cd pipeline op te stellen. Het probleem hiermee is dat elke 5 minuten er een pipeline zal runnen, ook al zou er een manier gevonden worden om niet constant pipelines te laten runnen die al gerunned zijn (hoog resource usage zonder benefit), is er nog altijd het probleem dat de pipelines niet gerunned worden op pushes, maar op een delay. Dit betekend dat teams afhankelijk zijn van een externe klok om hun ci test resultaten te kunnen bekijken.
