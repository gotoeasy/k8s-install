FROM alpine:3.14

MAINTAINER gotoeasy <gotoeasy@163.com>

# ---------------------------------------
# 本镜像收集网络资源以方便安装K8S
# ---------------------------------------

RUN mkdir -p /k8s-install/v1.23.3/canal && \
          cd /k8s-install/v1.23.3/canal && wget https://projectcalico.docs.tigera.io/manifests/canal.yaml --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/calico && \
          cd /k8s-install/v1.23.3/calico && wget https://docs.projectcalico.org/v3.11/manifests/calico.yaml --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/helm && \
          cd /k8s-install/v1.23.3/helm && wget https://get.helm.sh/helm-v3.8.0-linux-amd64.tar.gz --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/ingress-nginx && \
          cd /k8s-install/v1.23.3/ingress-nginx && wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/cloud/deploy.yaml --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/istio && \
          cd /k8s-install/v1.23.3/istio && wget https://github.com/istio/istio/releases/download/1.12.2/istio-1.12.2-linux-amd64.tar.gz --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/kubernetes-dashboard && \
          cd /k8s-install/v1.23.3/kubernetes-dashboard && wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/k9s && \
          cd /k8s-install/v1.23.3/k9s && wget https://github.com/derailed/k9s/releases/download/v0.25.18/k9s_Linux_x86_64.tar.gz --no-check-certificate && \
    cd / && \
       wget https://github.com/goharbor/harbor/releases/download/v2.4.1/harbor-offline-installer-v2.4.1.tgz --no-check-certificate && \
    tar -czf k8s-install.tar.gz k8s-install && rm -rf /k8s-install

