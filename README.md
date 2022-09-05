# Deploying simple experimental CI setup with orchestration, event queues and monitoring

The setup is deployed on 3 virtual machines, but should run on real hardware as well.

In this setup I use:

- Docker
- Kubernetes
- Kafka
- GitLab CI
- Prometheus
- Grafana

## Host configuration

- CPU: Intel Core i7-4790 3.6 GHz 4 cores / 8 threads
- RAM: 32 Gb
- Windows 7 x64

## Virtual machines configurations

Virtual machine 1 (Kubernetes master node):

- Ubuntu 18.04 x64
- 12Gb RAM
- 100 Gb Storage
- 4 cores
- Intel-VT enabled
- Network: NAT
- IP: 192.168.217.155

Virtual machine 2 (Kubernetes worker node 1):

- Ubuntu 18.04 x64
- 4Gb RAM
- 100 Gb Storage
- 4 cores
- Intel-VT enabled
- Network: NAT
- IP: 192.168.217.156

Virtual machine 3 (Kubernetes worker node 2):

- Ubuntu 18.04 x64
- 4Gb RAM
- 100 Gb Storage
- 4 cores
- Intel-VT enabled
- Network: NAT
- IP: 192.168.217.157

## Preparing setup

__Master & Workers__

First of all, let's update system on every virtual machine:
```
sudo apt-get update && sudo apt-get upgrade
```
Next read IP addresses of your virtual machines:
```
hostname -I | awk '{print $1}'
```
Then set hosts
```
sudo bash -c 'echo "192.168.217.155 kube-master" >> /etc/hosts'
sudo bash -c 'echo "192.168.217.156 kube-worker" >> /etc/hosts'
sudo bash -c 'echo "192.168.217.157 kube-worker2" >> /etc/hosts'
```
In order for Kubernetes to work we need to switch off swap:
```
sudo sed -i '/swapfile/d' /etc/fstab
sudo bash -c 'echo "3" > /proc/sys/vm/drop_caches'
sudo swapoff -a
sudo rm -f /swapfile
```

__Master__
```
hostnamectl set-hostname kube-master
```

__Worker 1__
```
hostnamectl set-hostname kube-worker
```

__Worker 2__
```
hostnamectl set-hostname kube-worker2
```

## Docker

__Master & Workers__

### Setting up Docker
```
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker
```

__Master__

### Adding a proxy Docker registry on port 5000

This will be used to store locally all images downloaded from the Internet. We can only download from it.
```
sudo docker run -e REGISTRY_STORAGE_DELETE_ENABLED="true" -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io -d -p 5000:5000 --restart=always --name registry-map2 registry:2
```

### Adding an internal Docker registry on port 6000

This will be used to store locally all images build by our system. We will upload and download from it.
```
sudo docker run -e REGISTRY_STORAGE_DELETE_ENABLED="true" -d -p 6000:5000 --restart=always --name registry registry:2
```

### Now we need to allow http insecure access to our registries

__Master & Workers__
```
sudo touch /etc/docker/daemon.json
sudo bash -c 'echo "{\"registry-mirrors\":[\"http://192.168.217.155:5000\"],\"insecure-registries\":[\"192.168.217.155:5000\",\"192.168.217.155:6000\"]}" >> /etc/docker/daemon.json'
sudo bash -c 'echo "DOCKER_OPTS=\"--config-file=/etc/docker/daemon.json\"" >> /etc/default/docker'
sudo systemctl restart docker
```

To see Docker status run:
```
sudo docker system info
```

## Kubernetes

__Master & Workers__

```
sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo sysctl net/netfilter/nf_conntrack_max=524288
sudo apt-get update && sudo apt-get install -y kubelet=1.24.3-00 kubeadm=1.24.3-00 kubectl=1.24.3-00
```

__Master__
```
sudo kubeadm init --control-plane-endpoint kube-master:6443 --pod-network-cidr 192.168.150.0/23 --upload-certs
```

At this step kubeadm will output a command to make worker nodes join the cluster starting *with sudo kubeadm join*. Save this command.

The join token will live for 24 hours, so when you need to generate another one, use these commands:
```
kubeadm token list
kubeadm token create --print-join-command
```

Now going on with the setup.

```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
You can start another terminal to watch for changes:
```
watch kubectl get pods --all-namespaces
```

__Workers__

Run the worker node join command you saved before, but remember to add "sudo" in the beginning, it will look something like 
```
sudo kubeadm join kube-master:6443 --token __some_token__ \
	--discovery-token-ca-cert-hash sha256:__some_hash_code__
```

__Master__

### Install Calico Nodes
```
curl -s https://docs.projectcalico.org/manifests/calico.yaml | \
sed \
-e 's|            # - name: CALICO_IPV4POOL_CIDR|            - name: CALICO_IPV4POOL_CIDR|g' \
-e "s|            #   value: \"192.168.0.0/16\"|              value: \"192.168.150.0/23\"|g" \
> calico.yaml
kubectl apply -f calico.yaml
kubectl get nodes
```



### Using Kubernetes dashboard

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.6.0/aio/deploy/recommended.yaml
kubectl proxy --address="192.168.217.155" -p 8001 --accept-hosts='^*$'
```

Then open http://192.168.217.155:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/ in a browser

### Configuring ContainerD

Latest versions of Kubernetes use ContainerD, so we need to configure insecure http image registries in it. 
```
sudo mkdir /etc/containerd
sudo gedit /etc/containerd/config.toml
```

Now set the registries' urls and save:
```
[plugins.cri.registry]
  [plugins.cri.registry.mirrors]
    [plugins.cri.registry.mirrors."192.168.217.155:5000"]
      endpoint = ["http://192.168.217.155:5000"]
    [plugins.cri.registry.mirrors."192.168.217.155:6000"]
      endpoint = ["http://192.168.217.155:6000"]
  [plugins.cri.registry.configs]
    [plugins.cri.registry.configs."192.168.217.155:5000".tls]
      insecure_skip_verify = true
    [plugins.cri.registry.configs."192.168.217.155:6000".tls]
      insecure_skip_verify = true
```
	
Now restart ContainerD:
```
sudo systemctl restart containerd
```

### To Uninstall Kubernetes
```
sudo kubeadm reset
rm -rf /etc/systemd/system/kubelnet.service.d
rm -rf $HOME/.kube/config
sudo apt-get remove --purge kubelet kubeadm kubectl
```


## Kafka

Ref: https://snourian.com/kafka-kubernetes-strimzi-part-1-creating-deploying-strimzi-kafka/
Ref: https://github.com/nrsina/strimzi-kafka-tutorial

```
git clone -b 0.30.0 https://github.com/strimzi/strimzi-kafka-operator.git
cd strimzi-kafka-operator
sed -i 's/namespace: .*/namespace: kafka/' install/cluster-operator/*RoleBinding*.yaml
kubectl create namespace kafka
kubectl create clusterrolebinding strimzi-cluster-operator-namespaced --clusterrole=strimzi-cluster-operator-namespaced --serviceaccount kafka:strimzi-cluster-operator
kubectl create clusterrolebinding strimzi-cluster-operator-entity-operator-delegation --clusterrole=strimzi-entity-operator --serviceaccount kafka:strimzi-cluster-operator
kubectl create clusterrolebinding strimzi-cluster-operator-topic-operator-delegation --clusterrole=strimzi-topic-operator --serviceaccount kafka:strimzi-cluster-operator
kubectl apply -f install/cluster-operator -n kafka
kubectl get deployments -n kafka
cp examples/kafka/kafka-ephemeral.yaml examples/kafka/kafka-ephemeral-2.yaml
gedit examples/kafka/kafka-ephemeral-2.yaml
```
Replace:
- 2 > 1
- 3 > 2

Add in spec->kafka->config:
```
auto.create.topics.enable: "true"
delete.topic.enable: "true"
```
Add in spec->kafka->listeners:
```
     - name: external
        port: 9094
        type: nodeport
        tls: false
```
Then do:
```
kubectl apply -f examples/kafka/kafka-ephemeral-2.yaml -n kafka
kubectl get deployments -n kafka
gedit kafka-topic.yaml
```
Set:
```
apiVersion: kafka.strimzi.io/v1beta1
kind: KafkaTopic
metadata:
  name: my-topic
  labels:
    strimzi.io/cluster: my-cluster
spec:
  partitions: 3
  replicas: 1
  config:
    retention.ms: 7200000
    segment.bytes: 1073741824
```	

```
kubectl apply -f kafka-topic.yaml -n kafka
kubectl get svc -n kafka
kubectl run kafka-producer -ti --image=strimzi/kafka:0.20.0-rc1-kafka-2.6.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --broker-list my-cluster-kafka-bootstrap.kafka:9092 --topic my-topic
kubectl run kafka-consumer -ti --image=strimzi/kafka:0.20.0-rc1-kafka-2.6.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka:9092 --topic my-topic --from-beginning
```

To user Kafka externally:
```
gedit kafka-external.yaml
```

Set:
```
apiVersion: v1
kind: Service
metadata:
  name: my-cluster-kafka-external-bootstrap
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: MyApp
  ports:
      # By default and for convenience, the `targetPort` is set to the same value as the `port` field.
    - port: 9094
      targetPort: 9094
      # Optional field
      # By default and for convenience, the Kubernetes control plane will allocate a port from a range (default: 30000-32767)
      nodePort: 30825
```

```
kubectl apply -f kafka-external.yaml -n kafka
```

To see the designated port, use:
```
kubectl get service --namespace kafka | grep external
```
You will get something like:
```
my-cluster-kafka-external-bootstrap   NodePort    10.106.223.28   <none>        9094:31318/TCP                        18m
```
So 31318 is the port you need.
	
To test Kafka external either use Kafka package:
```
cd ~
git clone -b 3.2.0 https://github.com/apache/kafka.git
cd kafka
./gradlew jar -PscalaVersion=2.13.6
bin/kafka-console-producer.sh --broker-list 192.168.217.155:31318 --topic my-topic
bin/kafka-console-consumer.sh --bootstrap-server 192.168.217.155:31318 --topic my-topic --from-beginning
```

Or use Kafka Cat:
```
sudo apt install -y kafkacat
echo "hello world!" | kafkacat -P -b 192.168.217.155:31318 -t my-topic
kafkacat -C -b 192.168.217.155:31318 -t my-topic
```
	
### Setup Strimzi Custom Producer / Consumer

From https://snourian.com/kafka-kubernetes-strimzi-part-2-creating-producer-consumer-using-go-scala-deploying-on-kubernetes/

```
cd ~
git clone https://github.com/nrsina/strimzi-kafka-tutorial.git

cd strimzi-kafka-tutorial/strimzi-producer

sudo docker build -t nrsina/strimzi-producer:v1 .

sudo docker tag nrsina/strimzi-producer:v1 192.168.217.155:6000/strimzi-producer:v1
sudo docker push 192.168.217.155:6000/strimzi-producer:v1

gedit deployment/deployment.yml
```

Set:
```
image: 192.168.217.155:6000/strimzi-producer:v1
imagePullPolicy: IfNotPresent
        - name: SP_SLEEP_TIME_MS
          value: "2000ms"
```

```
kubectl apply -f deployment/deployment.yml

kubectl logs -f strimzi-producer-deployment-7655d6c9d7-jjnfx

sdk install sbt
cd ~
cd strimzi-kafka-tutorial/strimzi-consumer
sudo chmod 666 /var/run/docker.sock
sbt docker:publishLocal

sudo docker tag nrsina/strimzi-consumer:v1 192.168.217.155:6000/strimzi-consumer:v1
sudo docker push 192.168.217.155:6000/strimzi-consumer:v1

gedit deployment/deployment.yml
```

Set:
```
replicas: 2
image: 192.168.217.155:6000/strimzi-consumer:v1
imagePullPolicy: IfNotPresent
```

```
kubectl apply -f deployment/deployment.yml

kubectl logs -f strimzi-consumer-deployment-f86469b6-c9cbt
```



## Prometheus

Open configurations:
```
gedit ~/strimzi-kafka-operator/examples/metrics/kafka-metrics.yaml
gedit ~/strimzi-kafka-operator/examples/kafka/kafka-ephemeral-2.yaml
```

Copy from kafka-metrics.yaml to kafka-ephemeral-2.yaml:
* metrics from spec->kafka->metricsConfig
* metrics from spec->zookeeper->metricsConfig
* all starting with

\-\-\-

kind: ConfigMap
	
...

```
kubectl apply -f ~/strimzi-kafka-operator/examples/kafka/kafka-ephemeral-2.yaml -n kafka
cd ~ && mkdir prometheus
cd ~/prometheus
```

```
curl -s https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/master/bundle.yaml > bundle.yaml
gedit bundle.yaml
```
Now replace:
```
namespace: default -> namespace: monitoring
```

```
kubectl create namespace monitoring
kubectl apply -f bundle.yaml -n monitoring --force-conflicts=true --server-side
kubectl get pods -n monitoring
kubectl get svc -n monitoring
cd ~/strimzi-kafka-operator/examples/metrics/prometheus-additional-properties
kubectl create secret generic additional-scrape-configs --from-file=prometheus-additional.yaml -n monitoring
kubectl apply -f prometheus-additional.yaml -n monitoring
cd ~/strimzi-kafka-operator/examples/metrics/prometheus-install
gedit strimzi-pod-monitor.yaml
```
Change:
```
myproject -> kafka
```

```
kubectl apply -f strimzi-pod-monitor.yaml -n monitoring
gedit prometheus.yaml
```
Change:
```
namespace: myproject -> namespace: monitoring
```

```
kubectl apply -f prometheus-rules.yaml -n monitoring
kubectl apply -f prometheus.yaml -n monitoring
kubectl get pods -n monitoring
```

## Grafana

```
cd ~/strimzi-kafka-operator/examples/metrics/grafana-install
kubectl apply -f grafana.yaml -n monitoring
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

- Open http://localhost:3000 
- Login with Username/password: admin
- Add Prometheus as a new Data Source.
- Set URL as http://prometheus-operated:9090
- Inside the Settings tap, you need to enter Prometheus address

```
kubectl get svc -n monitoring
```

Use addresses like:
- http://prometheus-operated:9090
- http://prometheus-operated.monitoring:9090 
- http://prometheus-operator.monitoring.svc.cluster.local:9090

Import these files through the Grafana webpage (select Prometheus datasource while importing):
- ~/strimzi-kafka-operator/examples/metrics/grafana-dashboards
- strimzi-kafka.json
- strimzi-kafka-exporter.json
- strimzi-operators.json
- strimzi-zookeeper.json


	
## Gitlab CI

Remove GitLab if already present:
```
sudo docker rm -f gitlab
```

Now install:
```
export GITLAB_HOME=/srv/gitlab
sudo docker run --detach \
  --hostname 192.168.217.155 \
  --publish 443:443 --publish 80:80 --publish 22:22 \
  --name gitlab \
  --restart always \
  --volume $GITLAB_HOME/config:/etc/gitlab \
  --volume $GITLAB_HOME/logs:/var/log/gitlab \
  --volume $GITLAB_HOME/data:/var/opt/gitlab \
  --shm-size 256m \
  gitlab/gitlab-ee:latest
```
To view GitLab logs:
```
sudo docker logs -f gitlab
```
Next get password:
```
sudo docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

Will get something like:
```
root
<password>
```

```
export GITLAB_CI_SERVER_URL=http://192.168.217.155
```

__Worker1__
```
sudo docker run -d --name gitlab-runner --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest
  
sudo docker run --rm -it -v /srv/gitlab-runner/config:/etc/gitlab-runner gitlab/gitlab-runner register

sudo gedit /srv/gitlab-runner/config/config.toml
```
Set:
```
[[runners]]
clone_url = "http://192.168.217.155/"
[runners.docker]
hostname = "http://192.168.217.155/"
image = docker:dind
privileged = true
```

```
sudo docker restart gitlab-runner
```

### To install Helm:
```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

Create git repo at: .gitlab/agents/testrusthyper-agent/config.yaml
```
gedit .gitlab/agents/testrusthyper-agent/config.yaml
```
Set:
```
ci_access:
  projects:
    - id: test-rust/hyper-1
```


Connect a Kubernetes cluster
Agent access token:

<TOKEN>

The agent uses the token to connect with GitLab.

You cannot see this token again after you close this window.
Install using Helm (recommended)

From a terminal, connect to your cluster and run this command. The token is included in the command.

```
sudo helm repo add gitlab https://charts.gitlab.io
sudo helm repo update
sudo helm upgrade --install testrusthyper-agent gitlab/gitlab-agent \
    --namespace gitlab-agent \
    --create-namespace \
    --set image.tag=v15.1.0 \
    --set config.token=<TOKEN> \
    --set config.kasAddress=ws://192.168.217.155/-/kubernetes-agent/
sudo helm upgrade testrusthyper-agent gitlab/gitlab-agent \
  --namespace gitlab-agent \
  --reuse-values \
  --set config.kasAddress=ws://192.168.217.155/-/kubernetes-agent/
```
To view GitLab logs:
```
kubectl logs -f -l=app=gitlab-agent -n gitlab-agent
```

## Test web service project in Rust/Hyper

### Setting up Rust

__Master__
```
sudo apt install -y build-essential
sudo curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

Then you need to get the Rust project from https://github.com/LumaRay/test-simple-web-server/tree/master/test-rust-hyper

```
cd ~/test-rust-hyper
cargo build --release
```

### Building Docker image
```
docker build --pull --rm -f "test.dockerfile" -t testrusthyper:latest "."
```

### Tagging, pushing, pulling
```
sudo docker tag testrusthyper:latest 192.168.217.155:6000/testrusthyper
sudo docker push 192.168.217.155:6000/testrusthyper
sudo docker pull 192.168.217.155:6000/testrusthyper
```
### Check the catalog:
```
sudo apt-get install curl
curl http://192.168.217.155:6000/v2/_catalog
curl -X GET 192.168.217.155:6000/v2/testrusthyper/tags/list
curl -X GET 192.168.217.155:6000/v2/testrusthyper/manifests/latest
```
