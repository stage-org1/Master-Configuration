# Opstellen High availibility kubernetes cluster

De eerste taak van de stage hield in dat we lokaal een high availibility kubernetes cluster moesten opstellen.

Hiervoor heb ik gebruik gemaakt van oracle’s virtualbox voor virtualisatie en een centos 7 image. Alle vm’s zaten samen in een subnet 10.0.2.x/24

10.0.2.2 Loadbalancer (haproxy) + ssh connectie naar host pc + ansible host
10.0.2.10 Master 1
10.0.2.11 Master 2
10.0.2.12 Master 3
10.0.2.20 Worker 1

## Ansible Setup

Eerst werden de ssh-keys gegenereerd en gecopieerd naar de andere vms (ssh-keygen ssh-copy-id). Hierna werden de ansible hosts gedefined:

[Masters]
10.0.2.10
10.0.2.11
10.0.2.12

[Workers]
10.0.2.20

[MainMaster]
10.0.2.10

[SecondaryMasters]
10.0.2.11
10.0.2.12

De reden dat we na de definitie van masters nog een aparte definitie hebben voor main en secondary is omdat voor een HA cluster op te stellen moeten we de secondary hosts joinen op een main host.

Hieronder de inhoud van het eerste ansible script (setup)

```
- hosts: all
  tasks:
    - name: test connection
      ping:
    - name: add kubernetes repo
      yum_repository:
        name: kubernetes
        description: "some repo"
        baseurl: https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
        enabled: yes
        gpgcheck: yes
        repo_gpgcheck: yes
        gpgkey: https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    - name: copy hosts file
      copy:
        src: hosts
        dest: /etc/hosts
    - name: ensure dns is in resolvconf
      command: echo "nameserver 8.8.8.8" > /etc/resolv.conf
    - name: setenforce 0 (linux perm step 1)
      command: setenforce 0
    - name: linux perm step 2
      replace:
        path: /etc/selinux/config
        regexp: 'SELINUX=enforcing'
        after: 'SELINUX=permissive'
    - name: update all packages
      yum:
        name: '*'
        state: latest
    - name: install kubernetes requirements
      yum:
        name: "{{ requirements }}"
      vars:
        requirements:
          - docker
          - kubeadm
          - kubectl
          - kubelet
    - name: enable and start docker service
      service:
        name: docker
        enabled: yes
        state: started
    - name: enable and start kubelet service
      service:
        name: kubelet
        enabled: yes
        state: started
    - name: open port 6443 tcp
      firewalld:
        zone: public
        permanent: yes
        state: enabled
        port: 6443/tcp
    - name: open port 10250 tcp
      firewalld:
        zone: public
        permanent: yes
        state: enabled
        port: 10250/tcp
    - name: open port 443 tcp
      firewalld:
        zone: public
        permanent: yes
        state: enabled
        port: 443/tcp

- hosts: Workers
  tasks:
    - name: open port range 30000-32767 tcp
      firewalld:
        zone: public
        permanent: yes
        state: enabled
        port: 30000-32767/tcp

- hosts: Masters
  tasks:
    - name: open port range 2379-2380 tcp (etcd)
      firewalld:
        zone: public
        permanent: yes
        state: enabled
        port: 2379-2380/tcp
    - name: open port 10251-10252 tcp (scheduler and controller manager)
      firewalld:
        zone: public
        permanent: yes
        state: enabled
        port: 10251-10252/tcp
```

Voor het installeren van kubernetes werden vele van deze commands gebaseerd op de inhoud van Creating Highly Available clusters with kubeadm

Config master 1 (dit is ook de setup voor de volgende masters en workers)

```
- hosts: MainMaster
  tasks:
    - name: disable swap
      command: swapoff -a
      ignore_errors: yes
    - name: force reset kubeadm for safety
      command: kubeadm reset -f
    - name: generateCert
      command: kubeadm alpha certs certificate-key
      register: cert
    - name: kubeadm init
      command: kubeadm init --control-plane-endpoint "10.0.2.2:6443" --upload-certs --certificate-key {{ cert.stdout }}
      ignore_errors: no
    - name: create .kube directory
      command: mkdir ~/.kube
      ignore_errors: yes
    - name: ensure dns server
      command: echo "nameserver 8.8.8.8" > /etc/resolv.conf
    - name: setup kubeconfig
      command: cp /etc/kubernetes/admin.conf ~/.kube/config
    - name: copy install weave
      copy:
        src: ~/installWeave.sh
        dest: ~/installWeave.sh
      ignore_errors: yes
    - name: make executable
      command: chmod +x installWeave.sh
    - name: weave setup
      command: sh ~/installWeave.sh
    - name: generate worker join command
      command: kubeadm token create --print-join-command
      register: joinOutput
    - name: save worker join
      local_action: copy content={{ joinOutput.stdout }} dest=~/join.sh
    - name: save master join
      local_action: copy content="{{ joinOutput.stdout }} --control-plane --certificate-key {{ cert.stdout }}" dest=~/joinMaster.sh
```

master 2 & 3 en worker 1

```
- hosts: SecondaryMasters
  tasks:
    - name: reset kubeadm for safety
      command: kubeadm reset -f
    - name: copy join command
      copy:
        src: joinMaster.sh
        dest: join.sh
    - name: make executable
      command: chmod +x join.sh
    - name: run join
      command: sh ./join.sh

- hosts: Workers
  tasks:
    - name: reset kubeadm for safety
      command: kubeadm reset -f
    - name: copy join
      copy:
        src: ./join.sh
        dest: ~/join.sh
    - name: run join
      command: ./join.sh
```

Door gebruik te maken van een experimenteel command om de certificate key te genereren kunnen we later samen met een command om de join command te genereren een join command opbouwen voor een master server.

Tenslotte volgt nog de configuratie file van de loadbalancer (in dit geval haproxy):

https://docs.kublr.com/articles/onprem-multimaster/

```
frontend kubernetes-api
	bind 10.0.2.2:6443
	bind 127.0.0.1:6443
	mode tcp
	option tcplog
	timeout client 300000
	default_backend kubernetes-api

backend kubernetes-api
	mode tcp
	option tcplog
	option tcp-check
		timeout server 300000
	balance roundrobin
	default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100

		server apiserver1 10.0.2.10:6443 check
		server apiserver2 10.0.2.11:6443 check
		server apiserver3 10.0.2.12:6443 check
```
