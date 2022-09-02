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

```
sudo apt-get install -y docker.io
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

__Then you can start another terminal to watch for changes__
```
watch kubectl get pods --all-namespaces
```

__Workers__

Run the worker node join command you saved before, it will look something like 
```
sudo kubeadm join kube-master:6443 --token __some_token__ \
	--discovery-token-ca-cert-hash sha256:__some_hash_code__
```



## Kafka

To install Kafka I used a very informative article https://snourian.com/kafka-kubernetes-strimzi-part-1-creating-deploying-strimzi-kafka/

## Test web service project in Rust/Hyper

## Gitlab CI

## Prometheus

## Grafana
