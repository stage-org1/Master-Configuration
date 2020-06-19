# Update: tekton pipelines in istio

Aangezien de tekton pipeline aangemaakt was voor dat we ons service mesh opgezet hebben, moeten we dit nog eens updaten.

## Namespace

We kunnen ook gebruik maken van de sidecar voor onze tekton pipeline dus we maken een namespace aan zodat we sidecar injection gemakkelijk kunnen enablen

```
---
apiVersion: v1
kind: Namespace
metadata:
  name: tekton-pipeline-istio-project-1
  labels:
    istio-injection: enabled #zorgt voor auto sidecar injection
```

## Service account and roles

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: service-acc
  namespace: tekton-pipeline-istio-project-1
secrets:
  - name: regcred
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: allow-creation
rules:
  - apiGroups:
      - ""
      - "apps"
      - "deploy"
      - "networking.istio.io"
    resources:
      - pods
      - serviceaccounts
      - namespaces
      - services
      - deployments
      - deployments.apps
      - destinationrules
      - gateways
      - virtualservices
    verbs:
      - list
      - watch
      - get
      - create
      - update
      - patch
      - delete
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: allow-creation-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: allow-creation
subjects:
  - kind: ServiceAccount
    name: service-acc
    namespace: tekton-pipeline-istio-project-1
```

Aangezien onze huidige deployments meer resource types gebruiken moeten we onze service account de rechten geven om deze up te daten. (jammer genoeg kan je hier geen wildcard operators gebruiken (*)). Opnieuw niet vergeten regcred aan te maken, deze keer gelinked aan de namespace.

## PipelineResources (git)

```
---
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: git-master
  namespace: tekton-pipeline-istio-project-1
spec:
  type: git
  params:
    - name: revision
      value: master
    - name: url
      value: git://github.com/beppevanrolleghem/cicdTest
---
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: git-experimental
  namespace: tekton-pipeline-istio-project-1
spec:
  type: git
  params:
    - name: revision
      value: experimental
    - name: url
      value: git://github.com/beppevanrolleghem/cicdTest
```

Deze keer maken we gebruik van een realistischere structuur. In plaats 2 verschillende mappen in 1 git repo te gebruiken voor A-B testen, gebruiken we deze keer 2 branches van dezelfde git repo. Deze moeten dus toegevoegd worden aan onze pipelineresources.

## Tasks

```
---
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: build-and-push
  namespace: tekton-pipeline-istio-project-1
spec:
  inputs:
    resources:
      - name: git-source
        type: git
    params:
      - name: context
        description: The path to the build context, used by Kaniko - within the workspace
        default: .
      - name: image-name
        description: dockerhub url
      - name: version
        description: image-version (for instance latest or beta)
  steps:
    - name: build-and-push
      image: gcr.io/kaniko-project/executor
      env:
        - name: "DOCKER_CONFIG"
          value: "/tekton/home/.docker/"
      command:
        - /kaniko/executor
      args:
        - "--dockerfile=$(inputs.resources.git-source.path)/$(inputs.params.context)/dockerfile"
        - "--destination=beppev/$(inputs.params.image-name):$(inputs.params.version)"
        - "--context=$(inputs.resources.git-source.path)/$(inputs.params.context)/"
---
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: destroy-application
  namespace: tekton-pipeline-istio-project-1
spec:
  inputs:
    resources:
      - name: git-source
        type: git
  steps:
    - name: delete-old-deployment
      image: lachlanevenson/k8s-kubectl
      command: ["kubectl"]
      args:
        - "delete"
        - "--ignore-not-found"
        - "-f"
        - "$(inputs.resources.git-source.path)/deploy.yaml"
---
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: deploy-application
  namespace: tekton-pipeline-istio-project-1
spec:
  inputs:
    resources:
      - name: git-source
        type: git
  steps:
    - name: deploy-new-app
      image: lachlanevenson/k8s-kubectl
      command: ["kubectl"]
      args:
        - "apply"
        - "-f"
        - "$(inputs.resources.git-source.path)/deploy.yaml"
```

Hoewel we hier een extra task bovenaan kunnen zien wordt deze uiteindelijk niet gebruikt. Tekton heeft de mogelijkheid nog niet om een gefaalde stap te skippen, en de destroy application stap zal een fout terug geven als er geen resources met die naam aanwezig zijn. Behalve dit zijn er enkele kleine aanpassingen gemaakt om de tasks makkelijker bruikbaar te maken.

## Pipeline

```
---
apiVersion: tekton.dev/v1alpha1
kind: Pipeline
metadata:
  name: application-pipeline
  namespace: tekton-pipeline-istio-project-1
spec:
  resources:
    - name: git-master
      type: git
    - name: git-experimental
      type: git
  tasks:
#  - name: destroy-application #@TODO make it so that #the delete can be skipped if error
#    taskRef:
#      name: destroy-application
#    resources:
#      inputs:
#        - name: git-source
#          resource: git-master
  - name: build-and-push-a
    taskRef:
      name: build-and-push
    params:
      - name: context
        value: "serverA"
      - name: image-name
        value: "server-a"
      - name: version
        value: "master"
    resources:
      inputs:
        - name: git-source
          resource: git-master
  - name: build-and-push-b-stable
    taskRef:
      name: build-and-push
    params:
      - name: context
        value: "serverB"
      - name: image-name
        value: "server-b"
      - name: version
        value: "master"
    resources:
      inputs:
        - name: git-source
          resource: git-master
  - name: build-and-push-b-experimental
    taskRef:
      name: build-and-push
    params:
      - name: context
        value: "serverB"
      - name: image-name
        value: "server-b"
      - name: version
        value: "experimental"
    resources:
      inputs:
        - name: git-source
          resource: git-experimental
  - name: build-and-push-d
    taskRef:
      name: build-and-push
    params:
      - name: context
        value: "serverD"
      - name: image-name
        value: "server-d"
      - name: version
        value: "master"
    resources:
      inputs:
        - name: git-source
          resource: git-master
  - name: deploy-application #@TODO make it so that the delete can be skipped if error
    taskRef:
      name: deploy-application
    runAfter:
      - build-and-push-d
      - build-and-push-b-experimental
      - build-and-push-a
      - build-and-push-b-stable
#      - destroy-application
    resources:
      inputs:
        - name: git-source
          resource: git-master
# DO NOT FORGET TO SET REGCREDS FOR DOCKER
```

En hier hebben we de uiteindelijke pipeline, met de destroy applicatie task uitgecomment. (uiteindelijk maakt deze stap niet super veel uit, maar het zou wel aangenaam zijn moest de structuur veranderen en oude resources zouden achter blijven)

