# Tekton Pipeline Follow up

Na wat meer experimenteren met Tekton Pipelines kan heb ik een beter zicht gekregen op hoe ik een cicd pipeline voor een project moet opstellen en zijn er enkele veranderingen gebeurt aan het project.

## HouseKeeping

Oorspronkelijk was de layout van het project de 4 services (frontend, backend, backend-experimental en mirror-service) samen met alle manifesten voor de infrastructuur in 1 repo. Dan branches voor de verschillende service mesh providers.

Dit kan perfect werken, maar het is niet zeer overzichtelijk, dus dit werd herbekeken en omgezet naar een realistischere opzet.

De eerste stap is alle services omzetten naar aparte repo’s. Dit betekend dat er nu 3 repo’s zijn voor de services: Stage-frontend, stage-backend en stage-mirror-service.

Dit kan grote voordelen hebben voor de pipeline (zal later besproken worden bij veranderingen pipeline). Al deze repo’s hebben ook een submodule infra, wat een aparte GitHub repo waar we gebruik zullen kunnen maken van de verschillende branches voor verschillende Service-Mesh-Providers.

## Pipeline-update

De Tekton Pipeline is herwerkt geweest voor 2 redenen, Er is een nieuwe versie van Tekton Pipeline uit die syntax veranderingen heeft (pipeline moest herschreven worden) en de veranderingen aan de GitHub repo’s.

Aangezien we met 3 repo’s werken kunnen we onze pipeline zo opbouwen dat deze werkt voor gelijk welke repo:branch. En dit is dus gebeurt.

## Tasks

In de laatste update van tekton werden pipeline resources deprecated verklaard, dit betekend dat de git-resource niet meer ondersteund zal worden in de toekomst. Ter vervanging van deze resource is er een hulp task: Git clone. Deze task cloned een git repo op een workspace (die gelinked kan worden aan een pvc of een emptyDir). In onze pipeline maken we gebruik van een pvc om deze git repo bij te houden omdat een workspace die gelinked is aan een emptyDir vervalt na elke stap. 

```
---
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: git-clone
  namespace: tekton-pipeline-1
spec:
  workspaces:
    - name: output
      description: workspace the repo will be cloned into
  params:
    - name: url
      description: git url to clone
      type: string
    - name: revision
      description: git revision to checkout (branch, tag, sha, ref…)
      type: string
      default: master
    - name: submodules
      description: defines if the resource should initialize and fetch the submodules
      type: string
      default: "true"
    - name: depth
      description: performs a shallow clone where only the most recent commit(s) will be fetched
      type: string
      default: "1"
    - name: sslVerify
      description: defines if http.sslVerify should be set to true or false in the global git config
      type: string
      default: "true"
    - name: subdirectory
      description: subdirectory inside the "output" workspace to clone the git repo into
      type: string
      default: "src"
    - name: deleteExisting
      description: clean out the contents of the repo's destination directory (if it already exists) before trying to clone the repo there
      type: string
      default: "true"
  results:
    - name: commit
      description: The precise commit SHA that was fetched by this Task
  steps:
    - name: clone
      image: gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:latest
      script: |
        CHECKOUT_DIR="$(workspaces.output.path)"
        cleandir() {
          if [[ -d "$CHECKOUT_DIR" ]] ; then
            rm -rf "$CHECKOUT_DIR"/*
            rm -rf "$CHECKOUT_DIR"/.[!.]*
            rm -rf "$CHECKOUT_DIR"/..?*
          fi
        }
        if [[ "$(params.deleteExisting)" == "true" ]] ; then
          cleandir
          ls -lah "$CHECKOUT_DIR"
        fi
        /ko-app/git-init \
          -url "$(params.url)" \
          -revision "$(params.revision)" \
          -path "$CHECKOUT_DIR" \
          -sslVerify "$(params.sslVerify)" \
          -submodules "$(params.submodules)" \
          -depth "$(params.depth)"
        cd "$CHECKOUT_DIR"
        RESULT_SHA="$(git rev-parse HEAD | tr -d '\n')"
        EXIT_CODE="$?"
        if [ "$EXIT_CODE" != 0 ]
        then
          exit $EXIT_CODE
        fi
        # Make sure we don't add a trailing newline to the result!
        echo -n "$RESULT_SHA" > $(results.commit.path)
```

## Event-listeners en triggers

Om volledig gebruik te kunnen maken van 4 repo’s moeten we onze pipeline en event-listeners zo opstellen dat ze enkel de laatste commits builden. Via het gebruik van Webhooks kunnen we de repo en branch van de laatste commit terugvinden, zo kunne we onze trigger-binding aanpassen:

```
---
apiVersion: tekton.dev/v1alpha1
kind: TriggerBinding
metadata:
  name: github-trigger-binding
  namespace: tekton-pipeline-1
spec:
  params:
  - name: gitrevision
    value: "$(body.head_commit.id)"
  - name: gitrepositoryurl
    value: "$(body.repository.clone_url)"
  - name: gitreponame
    value: $(body.repository.name)
```

en in ons trigger-template kunnen we dan deze variabelen gebruiken om de correcte repo’s te pullen, en de docker-images een naam+tag geven.

Om onze event-listener dan te exposeer kunnen we gebruik maken van een loadbalancer. Zolang we geen domain-name hebben kunnen we wel geen beveiligde Webhooks ontvangen, dus deze gebeuren wel nog via http. (event-listener + loadbalancer):

```
---
apiVersion: tekton.dev/v1alpha1
kind: EventListener
metadata:
  name: github-event-listener
  namespace: tekton-pipeline-1
spec:
  serviceAccountName: service-acc
  triggers:
    - name: github
      interceptors:
        - github:
            eventTypes: 
              - pull_request
              - push
      bindings:
        - name: github-trigger-binding
      template:
        name: github-trigger-template
---
apiVersion: v1
kind: Service
metadata:
  name: manual-service
  namespace: tekton-pipeline-1
spec:
  ports:
  - name: http-listener
    port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app.kubernetes.io/managed-by: EventListener
    app.kubernetes.io/part-of: Triggers
    eventlistener: github-event-listener
  type: LoadBalancer
```

## update 17/03

Nog vergeten te vermelden, maar er wordt nu gebruik gemaakt van conditionals om de pipeline van de infra repo te blocken (geen nut om pipeline een poging te laten doen om een dockerfile te builden die niet bestaat). als de mogelijkheid er komt om tasks over te slaan zal dit aangepast worden dat dit op de infra repo gebeurt .

Een ander punt is dat doorheen het testen van mijn pipeline merk ik op dat sommige keren kaliko extreem traag de images build, ik heb momenteel de images van python:3.7 veranderd naar python:3.7-alpine en het gaat al veel sneller. Ik heb ook skip-tls-verify meegegeven als parameter in de hoop van de push ook te versnellen. Momenteel lopen we op een 20 – 30 minuten buildtime wat een sterke verbetering is vs de oudere 60 – 90 min. Het zou kunnen dat ik mss ook eens zal kijken naar een nog lightere container, maar dat verzet het probleem gewoon verder. Het punt van de pipeline is voor functionaliteit van het dev team, en niet omgekeerd (dev team zou niet moeten buigen aan zwaktes platform)





