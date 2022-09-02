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

<u>Virtual machine 1 (Kubernetes master node):</u>
- Ubuntu 18.04 x64
- 12Gb RAM
- 100 Gb Storage
- 4 cores
- Intel-VT enabled
- Network: NAT
- IP: 192.168.217.155

<u>Virtual machine 2 (Kubernetes worker node 1):</u>
- Ubuntu 18.04 x64
- 4Gb RAM
- 100 Gb Storage
- 4 cores
- Intel-VT enabled
- Network: NAT
- IP: 192.168.217.156

<u>Virtual machine 3 (Kubernetes worker node 2):</u>
- Ubuntu 18.04 x64
- 4Gb RAM
- 100 Gb Storage
- 4 cores
- Intel-VT enabled
- Network: NAT
- IP: 192.168.217.157


## Kafka

To install Kafka I used a very informative article https://snourian.com/kafka-kubernetes-strimzi-part-1-creating-deploying-strimzi-kafka/

