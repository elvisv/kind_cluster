#!/bin/bash

KIND_CLUSTER_NAME="kind"

# create registry container unless it already exists
reg_name='kind-registry'
reg_port='5000'
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

# Create kind cluster with 2 worker nodes
kind create cluster --name "${KIND_CLUSTER_NAME}" --config kind_worker.yaml

# add the registry to /etc/hosts on each node
ip_fmt='{{.NetworkSettings.IPAddress}}'
cmd="echo $(docker inspect -f "${ip_fmt}" "${reg_name}") registry >> /etc/hosts"
for node in $(kind get nodes --name "${KIND_CLUSTER_NAME}"); do
  docker exec "${node}" sh -c "${cmd}"
  kubectl annotate node "${node}" \
          tilt.dev/registry=localhost:${reg_port} \
          tilt.dev/registry-from-cluster=registry:${reg_port}
done

# Install some testing software in the master node
#docker exec kind-control-plane sh -c 'apt-get update'
#docker exec kind-control-plane sh -c 'apt-get install git -y'
#docker exec kind-control-plane sh -c 'apt-get install build-essential -y'
#docker exec kind-control-plane sh -c 'curl -O https://storage.googleapis.com/golang/go1.14.1.linux-amd64.tar.gz'
#docker exec kind-control-plane sh -c 'tar -C /usr/local -xvzf go1.14.1.linux-amd64.tar.gz'
#docker exec kind-control-plane sh -c 'mkdir -p ~/go_projects/{bin,src,pkg}'
#docker exec kind-control-plane sh -c 'echo export GOPATH="/root/go_projects" >> ~/.bashrc'
#docker exec kind-control-plane sh -c 'echo export GOBIN="/root/go_projects/bin" >> ~/.bashrc'
#docker exec kind-control-plane sh -c 'echo PATH=$PATH:/usr/local/go/bin:/root/go_projects/bin >> ~/.bashrc'
#docker exec -e GOPATH='/root/go_projects' -e GOBIN='/root/go_projects/bin' kind-control-plane sh -c 'export PATH=$PATH:/usr/local/go/bin; go get github.com/coreos/etcd/etcdctl'
#docker exec -e GOPATH='/root/go_projects' -e GOBIN='/root/go_projects/bin' kind-control-plane sh -c 'export PATH=$PATH:/usr/local/go/bin; git clone https://github.com/jpbetz/auger;cd auger/;make build;cp ./build/auger /usr/local/bin/'


# Install the PSP polciies and RBAC
#kubectl apply -f psp/

# Install Calico
# https://alexbrand.dev/post/creating-a-kind-cluster-with-calico-networking/
kubectl apply -f calico.yaml
sleep 3s
# The RPF check is not enforced in Kind nodes. Thus, we need to disable the Calico check by setting an environment variable
kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true

# Install MetalLB and setup
# https://mauilion.dev/posts/kind-metallb/
kubectl apply -f metallb.yaml
# Before applying this you need to check by running.
#   docker network inspect bridge | grep IPAM -A7
# Modify addresses on kind-metalLB-config.yaml and specify a
# small range (~ 10 IPs) from within that IP range
kubectl apply -f kind-metalLB-config.yaml

# Install nginx Ingress Controller
# https://kubernetes.github.io/ingress-nginx/deploy/#bare-metal
kubectl apply -f nginx-ingress-mandatory.yaml
kubectl apply -f nginx-service-nodeport.yaml

# Install Istio
# https://istio.io/docs/setup/getting-started/
# Need to run the following first:
#
# curl -L https://istio.io/downloadIstio | sh -
# cd istio-*
# cp bin/istioctl /usr/local/bin/
#
# Go site on service meshes: layer5.io
#
#kubectl apply -f istio-operator.yaml
#kubectl apply -f istio-control-plane.yaml
#sleep 200
#istioctl manifest apply --set profile=demo --set values.global.mtls.auto=true --set values.global.mtls.enabled=false

# Install OPA Gatekeeper
# https://github.com/open-policy-agent/gatekeeper
#kubectl apply -f gatekeeper.yaml
#kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml

############### MONITORING ###############

# Install metrics-server
cd metrics-server
kubectl apply -f deploy/kubernetes/
cd ..

# Fix TLS issue with the metrics server in Kind
kubectl patch deployment metrics-server -n kube-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"metrics-server","args":["--cert-dir=/tmp", "--secure-port=4443", "--kubelet-insecure-tls","--kubelet-preferred-address-types=InternalIP"]}]}}}}'

# Install Prometheus for Monitoring
#helm repo add stable https://kubernetes-charts.storage.googleapis.com
#helm install my-prometheus-operator stable/prometheus-operator

############### UTILITIES ###############

#kubectl create namespace cert-manager
#helm install cert-manager cert-manager --repo https://charts.jetstack.io \
#  --set installCRDs=true \
#  --namespace cert-manager \
#  --wait

############### SAMPLE APP(s) ###############
#sleep 5s

cd sample/demo
# Build the local container locally and load it into the worker nodes
docker build -t localhost:5000/demo:testing-tag .
docker push localhost:5000/demo:testing-tag

#kind load docker-image demo:testing-tag

# Deploy the application
#cd ..
#kubectl apply -f demo/sample_app.yaml
# To reach your applicaiton, simply go to the external LB
# created for the ingress Controller
#   (get the external IP) k get svc -n ingress-nginx
#   (Try the app) curl http://<exteral_ip>

############### GATEKEEPER OPA SAMPLE ###############

# Deploy a policy to detect/block privileged containers
#  kubectl apply -f priv-container-template.yaml
# If you want to block privileged containers change
# enforcementAction: dryrun to enforcementAction: deny
# in priv-container-contraint.yaml
#   > kubectl apply -f priv-container-contraint.yaml
# To test the policy, create a privileged containerd
#   > kubectl apply -f attack-pod.yaml
# You can see the violation by describing the contraint
#   > k describe constraint psp-privileged-container

# TO DO: Istio example and Calico Network Policy example

# Once you are done with testing simply delete the clusters
# kind delete cluster
