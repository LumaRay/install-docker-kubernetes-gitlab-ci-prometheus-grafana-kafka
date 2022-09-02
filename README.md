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

```
sudo apt-get update && sudo apt-get upgrade
sudo echo "192.168.217.155 kube-master" >> /etc/hosts
sudo echo "192.168.217.156 kube-worker" >> /etc/hosts
sudo echo "192.168.217.157 kube-worker2" >> /etc/hosts
sudo /etc/init.d/networking restart
sudo netplan apply
sudo sed -i '/swapfile/d' /etc/fstab
sudo echo "3" > /proc/sys/vm/drop_caches
sudo swapoff -a
sudo rm -f /swapfile
```

__Master__
```
hostnamectl set-hostname master-node
```

__Worker 1__
```
hostnamectl set-hostname worker-node
```

__Worker 2__
```
hostnamectl set-hostname worker-node2
```

## Docker

__Master__

### Setting up Docker
```
sudo apt-get install -y docker.io
```

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
sudo touch /etc/docker/daemon.json && sudo echo '{"registry-mirrors":["http://192.168.217.155:5000"],"insecure-registries":["192.168.217.155:5000","192.168.217.155:6000"]}' > /etc/docker/daemon.json
sudo echo 'DOCKER_OPTS="--config-file=/etc/docker/daemon.json"' > /etc/default/docker
sudo systemctl stop docker && sudo systemctl start docker
```

To see Docker status run:
```
sudo docker system info
```

To list the catalog:
```
curl http://192.168.217.155:6000/v2/_catalog
curl -X GET 192.168.217.155:6000/v2/testrusthyper/tags/list
curl -X GET 192.168.217.155:6000/v2/testrusthyper/manifests/latest
```



## Kubernetes

__Master & Workers__

```
sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
```

__Master__
```
sudo kubeadm init --control-plane-endpoint kube-master:6443 --pod-network-cidr 192.168.150.0/23
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
curl -s https://docs.projectcalico.org/manifests/calico.yaml | \
sed \
-e 's|            # - name: CALICO_IPV4POOL_CIDR|            - name: CALICO_IPV4POOL_CIDR|g' \
-e "s|            #   value: \"192.168.0.0/16\"|              value: \"192.168.150.0/23\"|g"
kubectl apply -f calico.yaml
kubectl get nodes
```

Then you can start another terminal to watch for changes:
```
watch kubectl get pods --all-namespaces
```


__Workers__

Run the worker node join command you saved before, it will look something like 
```
sudo kubeadm join kube-master:6443 --token __some_token__ \
	--discovery-token-ca-cert-hash sha256:__some_hash_code__
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
kubectl get nodes -o wide
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


## Kafka

To install Kafka I used a very informative article https://snourian.com/kafka-kubernetes-strimzi-part-1-creating-deploying-strimzi-kafka/

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

## Gitlab CI

## Prometheus

Edit configurations:
```
gedit ~/strimzi-kafka-operator/examples/metrics/kafka-metrics.yaml
gedit ~/strimzi-kafka-operator/examples/kafka/kafka-ephemeral-2.yaml
```

Copy metrics

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
- Add Prometheus as a new Data Source.
- Inside the Settings tap, you need to enter Prometheus address

```
kubectl get svc -n monitoring
```

Use addresses like:
- http://prometheus-operated:9090
- http://prometheus-operated.monitoring:9090 
- http://prometheus-operator.monitoring.svc.cluster.local:9090

Import these files through the Grafana webpage:
- ~/strimzi-kafka-operator/examples/metrics/grafana-dashboards
- strimzi-kafka.json
- strimzi-kafka-exporter.json
- strimzi-operators.json
- strimzi-zookeeper.json
