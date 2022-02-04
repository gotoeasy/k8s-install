FROM alpine:3.14

MAINTAINER gotoeasy <gotoeasy@163.com>

# ------------------------------
# 本镜像收集网络资源方便安装K8S
# ------------------------------

RUN mkdir -p /k8s-install/v1.23.3/canal && \
          cd /k8s-install/v1.23.3/canal && wget https://projectcalico.docs.tigera.io/manifests/canal.yaml --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/helm && \
          cd /k8s-install/v1.23.3/helm && wget https://get.helm.sh/helm-v3.8.0-linux-amd64.tar.gz --no-check-certificate && \
    mkdir -p /k8s-install/v1.23.3/ingress-nginx && \
          cd /k8s-install/v1.23.3/ingress-nginx && wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/cloud/deploy.yaml --no-check-certificate && \
    cd / && \
    tar -czf k8s-install.tar.gz k8s-install && rm -rf /k8s-install

