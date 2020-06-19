# Kubernetes demo applicatie

Om onze cluster te testen moet er een demo applicatie gecreëerd worden, en aangezien dat we later gaan werken met service meshes zorgen we best dat er pod to pod communicatie gebeurt via een service.

## layout/plan

Het concept is om 2 servers te hebben, die allebei antwoorden op requests. server a zal 2 urls hebben waar ze bepaalde antwoorden op geeft:

/ : Op deze url zal server a een bericht achter laten dat de server werkt. Dit is een makkelijke manier om te testen of de expose werkt zonder pod 2 pod communicatie te moeten gebruiken. (want als de error daar zou zitten is het moeilijker op te merken)

/check : op deze url zal server a een request doen naar server b en de output ervan doorsturen als antwoord op het oorspronkelijke request

server b zal een zeer simpel antwoord geven op server a, maar later kunnen we meer variabelen steken in dit antwoord om verschillende testen te kunnen uitvoeren.

server a zal verbonden zijn met server b via de service “server-check”, en server a zal exposed worden via de service “expose-server” met nodeport 30036

## Server a

Voor deze servers op te stellen kunnen we gemakkelijk gebruik maken van flask om een simpele webserver op te starten. Beide servers hebben dus een dockerfile, een app.py en een requirements.txt

Dit is de inhoud van app.py van server a:

```
from flask import Flask
import requests

app = Flask(__name__)

URL = "http://server-check:6000"


@app.route('/')
def doRequest():
    return "it works"

@app.route('/check')
def itWorks():
    return requests.get(URL).json()


if __name__ == '__main__':
    app.run(debug=True, host="0.0.0.0", port=5000)
```

en de dockerfile van server a:

```
from python:3.7

copy . /app
workdir /app

run pip install -r requirements.txt
expose 5000
entrypoint [ "python" ]

cmd [ "app.py" ]
```

## Server b

zeer gelijkaardige configuratie als server a, maar gebruikt poort 6000 en heeft maar 1 url

app.py

```
from flask import Flask
from flask import jsonify
app = Flask(__name__)


@app.route('/')
def doRequest():
    data = {
        "serverName": "serverB",
        "success": "true"
    }
    return jsonify(data)


if __name__ == '__main__':
    app.run(debug=True, host="0.0.0.0", port=6000)
```

dockerfile

```
from python:3.7

copy . /app
workdir /app

run pip install -r requirements.txt
expose 6000
entrypoint [ "python" ]

cmd [ "app.py" ]
```

## Manifests/deploy.yaml

om dit allemaal te kunnen laten werken moeten er pods en services aangemaakt worden, en dit is waarvoor deze file dient. Deze file is een collectie van al deze resources zodat ze in 1 keer gecreeerd kunnen worden:

```
---
apiVersion: v1
kind: Pod
metadata:
  name: server-a
  labels:
    server: "http"
    expose: "true"
spec:
  containers:
    - name: front-end
      image: beppev/server-a:latest
      ports:
        - containerPort: 5000
---
apiVersion: v1
kind: Pod
metadata:
  name: server-b
  labels:
    server: "http"
spec:
  containers:
    - name: front-end
      image: beppev/server-b:latest
      ports:
        - containerPort: 6000
---
kind: Service
apiVersion: v1
metadata:
  name: server-check
spec:
  selector:
    server: "http"
  ports:
    - name: http
      protocol: TCP
      port: 6000
---
kind: Service
apiVersion: v1
metadata:
  name: expose-server
spec:
  type: NodePort
  selector:
    expose: "true"
  ports:
    - name: http
      protocol: TCP
      targetPort: 5000
      port: 5000
      nodePort: 30036
```





