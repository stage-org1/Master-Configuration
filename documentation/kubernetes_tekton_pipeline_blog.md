# Kubernetes tekton pipeline

tekton bied de mogelijkheid om een pipeline te hosten in de kubernetes cluster waar de uiteindelijke applicatie gedeployed moet worden

## Vooropzet

Om deze pipeline te kunnen opzetten moet er eerst wat vooropzet gebeuren. Ten eerste moeten we tekton pipelines installeren op onze kubernetes cluster, dit kunnen we doen via de command

```
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

Dit geeft ons toegang tot de tekton api in kubernetes, wat ons de mogelijkheid bied om tasks, pipelineresources, pipelines en andere objecten te kunnen aanmaken. Deze zullen we later gebruiken om de eigenlijke pipeline te builden.

Om de pipeline te laten werken heeft deze een service account nodig. Deze dient om de pipeline mogelijkheid te geven tot het deployen van pods en andere objecten, en geeft ons de mogelijkheid om bepaalde secrets aan deze service account te linken (zoals de docker-hub credentials).

Service account

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tutorial-service
secrets:
  - name: regcred
```

docker credentials

```
kubectl create secret docker-registry regcred \
                    --docker-server=<your-registry-server> \
                    --docker-username=<your-name> \
                    --docker-password=<your-pword> \
                    --docker-email=<your-email>
```

nadat de docker credentials aan de service account hangen moeten we deze nog rechten geven om pods, services en deployments te deployen, met deze command creeren we een rol die deployments, pods en services kan (getten, listen, etc) aanpassen.

```
kubectl create clusterrole tutorial-role \
               --verb=get,list,watch,create,update,patch,delete \
               --resource=deployments,deployments.apps,pods,services
```

en met deze command kunnen we deze linken aan de tutorial-service user die we eerder aangemaakt hebben.

```
kubectl create clusterrolebinding tutorial-binding \
             --clusterrole=tutorial-role \
             --serviceaccount=default:tutorial-service
```

## bouwen van de pipeline

de pipeline bestaat uit verschillende blokken die samenwerken en uiteindelijk samengebracht worden in een pipeline object. Hieronder zal elk van deze blokken beschreven worden.

### Resources 

onze enige resource voor dit project is de git repo die we gebruiken om onze pipeline op te runnen:

```
---
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: git
spec:
  type: git
  params:
    - name: revision
      value: master
    - name: url
      value: git://github.com/beppevanrolleghem/cicdTest
```

deze kunnen we later aanroepen en helpt ons met navigatie van bestanden in de repo die nodig zijn voor bv builden van containers

## Tasks

dit zijn de tasks voor onze pipeline, en we kunnen ze opbouwen als functies die argumenten lezen en uitkomsten weergeven. Voor deze opdracht moeten we de uitkomsten van de functies niet gebruiken, maar deze mogelijkheid bestaat wel.
Build and push

deze stap build de docker containers en pushed ze naar docker hub

```
---
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: build-and-push
spec:
  inputs:
    resources:
      - name: git-source
        type: git
    params:
      - name: pathToContext
        description: The path to the build context, used by Kaniko - within the workspace
        default: .
      - name: pathToDockerfile
        description: The path to the dockerfile to build
        default: Dockerfile
      - name: imageUrl
        description: value should be like - us.icr.io/test_namespace/builtImageApp
      - name: imageTag
        description: Tag to apply to the built image
  steps:
    - name: build-and-push
      image: gcr.io/kaniko-project/executor
      env:
        - name: "DOCKER_CONFIG"
          value: "/tekton/home/.docker/"
      command:
        - /kaniko/executor
      args:
        - "--dockerfile=dockerfile"
        - "--destination=beppev/$(inputs.params.imageUrl):$(inputs.params.imageTag)"
        - "--context=$(inputs.resources.git-source.path)/$(inputs.params.pathToContext)/"
```

door de environment variable docker_config aan te duiden en deze te linken aan /tekton/home/.docker (normaal gezien is deze /kaniko/.docker) kunnen we onze eerder aangemaakte docker credentials gebruiken om onze containers te pushen naar de docker registry.

## Deploy application

deze task deployed een kubernetes manifest op de cluster, in ons geval gebruiken we deploy.yaml in de root van onze git repo.

```
---
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: deploy-application
spec:
  inputs:
    resources:
      - name: git-source
        type: git
    params:
      - name: pathToContext
        description: The path to the build context, used by Kaniko - within the workspace
        default: .
      - name: pathToYamlFile
        description: The path to the yaml file to deploy within the git source
        default: deploy.yaml
      - name: imageUrl-a
        description: Url of image repository
        default: url
      - name: imageTag-a
        description: Tag of the images to be used.
        default: "latest"
      - name: imageUrl-b
        description: Url of image repository
        default: url
      - name: imageTag-b
        description: Tag of the images to be used.
        default: "latest"
  steps:
    - name: replace-imagea
      image: alpine
      command: ["sed"]
      args:
        - "-i"
        - "-e"
        - "s;IMAGE-A;$(inputs.params.imageUrl-a):$(inputs.params.imageTag-a);g"
        - "$(inputs.resources.git-source.path)/$(inputs.params.pathToContext)/$(inputs.params.pathToYamlFile)"
    - name: replace-imageb
      image: alpine
      command: ["sed"]
      args:
        - "-i"
        - "-e"
        - "s;IMAGE-b;$(inputs.params.imageUrl-b):$(inputs.params.imageTag-b);g"
        - "$(inputs.resources.git-source.path)/$(inputs.params.pathToContext)/$(inputs.params.pathToYamlFile)"
    - name: deploy-app
      image: lachlanevenson/k8s-kubectl
      command: ["kubectl"]
      args:
        - "apply"
        - "-f"
        - "$(inputs.resources.git-source.path)/deploy.yaml"
```

## Pipeline

dit object zet de juiste stappen in de juiste volgorde zodat ons deployment vlot verloopt

```
apiVersion: tekton.dev/v1alpha1
kind: Pipeline
metadata:
  name: application-pipeline
spec:
  resources:
    - name: git-source
      type: git
  params:
    - name: pathToYamlFile
      description: path to deploy.yaml for final application deploy
      default: config.yaml
    - name: pathToContext
      description: The path to the build context, used by Kaniko - within the workspace
      default: .
    - name: imageUrl-a
      description: Url of image repository a
      default: deploy_target
    - name: imageTag-a
      description: Tag to apply to the built image a
      default: latest
    - name: pathToContext-a
      description: The path to the build context, used by Kaniko - within the workspace
      default: .
    - name: imageUrl-b
      description: Url of image repository
      default: deploy_target
    - name: imageTag-b
      description: Tag to apply to the built image
      default: latest
    - name: pathToContext-b
      description: The path to the build context, used by Kaniko - within the workspace
      default: .
  tasks:
  - name: build-and-push-a
    taskRef:
      name: build-and-push
    params:
      - name: pathToContext
        value: "$(params.pathToContext-a)"
      - name: imageUrl
        value: "$(params.imageUrl-a)"
      - name: imageTag
        value: "$(params.imageTag-a)"
    resources:
      inputs:
        - name: git-source
          resource: git-source
  - name: build-and-push-b
    taskRef:
      name: build-and-push
    runAfter:
      - build-and-push-a
    params:
      - name: pathToContext
        value: "$(params.pathToContext-b)"
      - name: imageUrl
        value: "$(params.imageUrl-b)"
      - name: imageTag
        value: "$(params.imageTag-b)"
    resources:
      inputs:
        - name: git-source
          resource: git-source
  - name: deploy-application
    taskRef:
      name: deploy-application
    runAfter:
      - build-and-push-b
    params:
      - name: pathToContext
        value: "."
      - name: pathToYamlFile
        value: "deploy.yaml"
      - name: imageUrl-a
        value: "$(params.imageUrl-a)"
      - name: imageTag-a
        value: "$(params.imageTag-a)"
      - name: imageUrl-b
        value: "$(params.imageUrl-b)"
      - name: imageTag-b
        value: "$(params.imageTag-b)"
    resources:
      inputs:
        - name: git-source
          resource: git-source
```

## pipeline run

Dit is de laatste stap van de pipeline op te bouwen, vergeet niet alle eerdere stappen te applyen voordat je deze runned.

```
apiVersion: tekton.dev/v1alpha1
kind: PipelineRun
metadata:
  name: application-pipeline-run
spec:
  serviceAccountName: tutorial-service
  pipelineRef:
    name: application-pipeline
  resources:
    - name: git-source
      resourceRef:
        name: git
  params:
    - name: pathToYamlFile
      value: "deploy.yaml"
    - name: pathToContext
      value: "."
    - name: imageUrl-a
      value: "server-a"
    - name: imageTag-a
      value: "latest"
    - name: pathToContext-a
      value: "./serverA"
    - name: imageUrl-b
      value: "server-b"
    - name: imageTag-b
      value: "latest"
    - name: pathToContext-b
      value: "./serverB"
```

Dit object is vooral verantwoordelijk voor alle variabelen correct te stellen zodat ze makkelijk gebruikt kunnen worden in de andere tasks.



