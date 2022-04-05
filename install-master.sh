#!/bin/bash

# ============================================================================================
# 本脚本使用root账号安装，在AnolisOS 7.9基础上成功，理应兼容CentOS 7.x
# ============================================================================================

# ------------------------------------------
# 1）环境变量
# ------------------------------------------
# 本机IP使用网卡eth0的IP
ETH0IP=$(/sbin/ifconfig eth0 | awk '/inet / {print $2}')
# K8S版本
export K8SVER=1.23.3

# ------------------------------------------
# 2）系统基础环境设定
# ------------------------------------------
cd
# 时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone
echo 'LANG="zh_CN.UTF-8"' > /etc/locale.conf
source /etc/locale.conf
date

# 同步服务器时间
# ntpdate cn.pool.ntp.org
# date

# 永久关闭防火墙
systemctl stop firewalld && systemctl disable firewalld

# 永久关闭selinux，查看状态 sestatus
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config;cat /etc/selinux/config

# 永久禁用swap
swapoff -a
sed -i.bak '/swap/s/^/#/' /etc/fstab

# 内核参数修改
# https://kubernetes.io/zh/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system


# ------------------------------------------
# 3）配置镜像源安装docker
# ------------------------------------------
# 配置镜像源
wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O /etc/yum.repos.d/docker-ce.repo
# 查看版本例子 yum list docker-ce.x86_64 --showduplicates
# 默认安装最新版时，不需要指定版本号
#yum -y install docker-ce

# 安装指定版
yum -y install docker-ce-20.10.12-3.el7
#docker -v

# 修改docker cgroup驱动，与k8s一致，设定docker镜像加速，docker配置不少按需修改
mkdir -p /etc/docker
mkdir -p /opt/docker/data-root
cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "/opt/docker/data-root",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://8k7wmbfp.mirror.aliyuncs.com","https://docker.mirrors.ustc.edu.cn"]
}
EOF

# 设定docker开机启动
#systemctl daemon-reload
systemctl enable docker
systemctl start docker
#docker info

# ------------------------------------------
# 4）下载要用到各资源文件，免除繁琐的网络问题
# ------------------------------------------
# 下载
docker pull registry.cn-shanghai.aliyuncs.com/gotoeasy/k8s-install
docker run -d --name gotoeasy-k8s-install registry.cn-shanghai.aliyuncs.com/gotoeasy/k8s-install sh
docker cp gotoeasy-k8s-install:/k8s-install.tar.gz .
docker stop gotoeasy-k8s-install && docker rm gotoeasy-k8s-install && docker rmi registry.cn-shanghai.aliyuncs.com/gotoeasy/k8s-install
tar -xzf k8s-install.tar.gz
rm -f k8s-install.tar.gz
cd ~/k8s-install/v1.23.3/ingress-nginx

# 修改两个镜像包避免无法拉取
sed -i 's@k8s.gcr.io/ingress-nginx/controller:v1\(.*\)@registry.cn-shanghai.aliyuncs.com/gotoeasy/devops:ingress-nginx-controller-v1.1.1@' deploy.yaml
sed -i 's@k8s.gcr.io/ingress-nginx/kube-webhook-certgen:v1\(.*\)$@registry.cn-shanghai.aliyuncs.com/gotoeasy/devops:kube-webhook-certgen-v1.1.1@' deploy.yaml

# 把Deployment改成DaemonSet以便在每个node上都开启一个实例
sed -i 's@Deployment$@DaemonSet@' deploy.yaml
# 开启hostNetwork 启用80、443端口 hostNetwork: true
sed -i '/dnsPolicy: ClusterFirst/i\      hostNetwork: true' deploy.yaml
# 绑定宿主机ip地址 watch-ingress-without-class=true
sed -i '/validating-webhook-key/a\            - --watch-ingress-without-class=true' deploy.yaml
cd

# policy/v1beta1将弃用，改为policy/v1
cd ~/k8s-install/v1.23.3/canal
sed -i 's@policy/v1beta1@policy/v1@' canal.yaml
cd

# 修改metrics-server的镜像包避免无法拉取
cd ~/k8s-install/v1.23.3/metrics-server
sed -i 's@k8s.gcr.io/metrics-server/metrics-server:v\(.*\)@registry.cn-shanghai.aliyuncs.com/gotoeasy/devops:metrics-server-v0.6.1@' components.yaml
# 参数含metric-resolution的后面加一行参数，取消证书验证
sed -i '/metric-resolution/a\        - --kubelet-insecure-tls' components.yaml
cd


# ------------------------------------------
# 5）安装kubernetes
# ------------------------------------------
# 配置镜像源
cat >/etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

# 若是要安装特定版本，可先查看确认下，k8s的1.20版本开始默认不使用docker
# 查看版本例子 yum list kubelet --showduplicates
# 安装kubeadm（会自动安装kubele、kubectl），不指定版本号时默认安装最新版，如 yum install -y kubeadm
# 安装指定版
yum install -y kubeadm-$K8SVER
#kubectl version

# 可选： kubectl和kebuadm命令tab健补齐，执行以下命令后退出当前终端生效
kubectl completion bash >/etc/bash_completion.d/kubectl
kubeadm completion bash >/etc/bash_completion.d/kubeadm

# 设定kubelet开机启动
systemctl enable kubelet
systemctl start kubelet

# 初始化kubeadm，使用阿里镜像仓库地址，环境变量指定本机IP，版本参数保持和kubectl version查的一致
#service-node-port-range
kubeadm init \
--apiserver-advertise-address=$ETH0IP \
--image-repository registry.aliyuncs.com/google_containers \
--kubernetes-version v$K8SVER \
--service-cidr=10.96.0.0/12 \
--pod-network-cidr=10.244.0.0/16

# 重建token保存到文件
#kubeadm token create --print-join-command > $HOME/kubeadm-init-result.txt

# 拷贝kubectl使用的连接k8s认证文件到默认路径给非root用户使用
#mkdir -p $HOME/.kube
#cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#chown $(id -u):$(id -g) $HOME/.kube/config

# 若是root用户就直接使用admin.conf
echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /etc/profile

# 命令别名
echo 'alias d=docker' >> /etc/profile
echo 'alias k=kubectl' >> /etc/profile
# 支持别名k命令tab健补齐
echo 'complete -F __start_kubectl k' >> /etc/profile

source /etc/profile

# 执行kubectl get nodes查看状态，此时为 NotReady，需要初始化虚拟网络
kubectl apply -f ~/k8s-install/v1.23.3/canal/canal.yaml


# 查看(等待初始化完成)
#docker images
#kubectl get pods -n kube-system
#kubectl get nodes

echo '可用 kubectl get pods -n kube-system 查看状态，等待几分钟直到全部就绪'

# 允许master发布pod，其中masterhostname是主机名
#kubectl taint node masterhostname node-role.kubernetes.io/master-
#或 kubectl taint nodes --all node-role.kubernetes.io/master-

# ------------------------------------------
# 6）安装helm，如ingress-nginx中有按helm引用安装
# ------------------------------------------
cd ~/k8s-install/v1.23.3/helm
tar -zxf helm-v3.8.0-linux-amd64.tar.gz
mv  linux-amd64/helm  /usr/local/bin/helm
cd
helm version
# 修改镜像源
helm repo remove stable
helm repo add stable https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
helm repo add aliyuncs https://apphub.aliyuncs.com
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm repo list
#helm search repo mysql

# ------------------------------------------
# 7）安装Istio
# ------------------------------------------
#cd ~/k8s-install/v1.23.3/istio
#tar xzf istio-1.12.2-linux-amd64.tar.gz
#mv istio-1.12.2 /opt/istio
#echo 'export ISTIO_HOME=/opt/istio' >> /etc/profile
#echo 'export PATH=$PATH:$ISTIO_HOME/bin' >> /etc/profile
#source /etc/profile
#istioctl version

#安装 https://www.cnblogs.com/huanglingfa/p/13895297.html
#istioctl manifest apply --set profile=demo
#查询部署完成情况
#kubectl get svc -n istio-system
#kubectl get pods -n istio-system

# ------------------------------------------
# 8）安装ingress-nginx
# ------------------------------------------
kubectl apply -f ~/k8s-install/v1.23.3/ingress-nginx/deploy.yaml
kubectl get service -n ingress-nginx
kubectl get pods --namespace=ingress-nginx

# ------------------------------------------
# 9）安装k9s
# ------------------------------------------
cd ~/k8s-install/v1.23.3/k9s
tar xzf k9s_Linux_x86_64.tar.gz
mv k9s /usr/local/bin
cd

# ------------------------------------------
# 10）安装kubernetes-dashboard
# ------------------------------------------
#kubectl apply -f ~/k8s-install/v1.23.3/kubernetes-dashboard/recommended.yaml
#kubernetes-dashboard默认default名称空间权限，按下面步骤操作可有全部名称空间权限
#kubernetes-dashboard 创建管理员token，可查看任何空间权限
#kubectl create clusterrolebinding dashboard-cluster-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:kubernetes-dashboard
#查看kubernetes-dashboard名称空间下的secret
#kubectl -n kubernetes-dashboard get secret
#找到对应的带有token的 kubernetes-dashboard-token-xxxx, 然后查看其token
#kubectl -n kubernetes-dashboard describe secret kubernetes-dashboard-token-
#最后根据需要配置ingress或暴露service端口供外网访问

# ------------------------------------------
# 11）安装metrics-server(节点群建起来后再装吧)
# ------------------------------------------
#kubectl apply -f ~/k8s-install/v1.23.3/metrics-server/components.yaml

# ------------------------------------------
# 12）安装gitlab-runner（helm 0.38.1 基础上修改）
# ------------------------------------------
# gitlab管理资源文件 -> gitlab-runner -> 部署
# 替换gitlab-runner.tar中的gitlab地址及令牌
# 创建命名空间、创建minio访问秘钥、安装
# kubectl create namespace gitlab-runner
# kubectl create secret generic s3access --from-literal=accesskey="minio" --from-literal=secretkey="password.123" -n gitlab-runner
# helm install --name-template cicd -f values.yaml . --namespace gitlab-runner

