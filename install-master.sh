#!/bin/bash

# ============================================================================================
# 本脚本使用root账号安装，适用于兼容CentOS7的初始镜像，如阿里云的CentOS 7.9、AnolisOS 7.9
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

# 同步服务器时间
# yum install chrony -y
# systemctl enable chronyd
# systemctl start chronyd
# chronyc sources
# date

# 永久关闭防火墙
systemctl stop firewalld && systemctl disable firewalld

# 永久关闭selinux
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config;cat /etc/selinux/config

# 永久禁用swap
swapoff -a
sed -i.bak '/swap/s/^/#/' /etc/fstab

# 内核参数修改
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
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
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://8k7wmbfp.mirror.aliyuncs.com","https://docker.mirrors.ustc.edu.cn"]
}
EOF

# 设定docker开机启动
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
sed -i 's@k8s.gcr.io/ingress-nginx/controller:v1\(.*\)@registry.cn-shanghai.aliyuncs.com/gotoeasy/ingress-nginx-controller:v1.1.1@' deploy.yaml
sed -i 's@k8s.gcr.io/ingress-nginx/kube-webhook-certgen:v1\(.*\)$@registry.cn-shanghai.aliyuncs.com/gotoeasy/ingress-nginx-kube-webhook-certgen:v1.1.1@' deploy.yaml
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
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm repo list
helm search repo mysql

# ------------------------------------------
# 7）安装Istio
# ------------------------------------------
cd ~/k8s-install/v1.23.3/istio
tar xzf istio-1.11.6-linux-amd64.tar.gz
mv istio-1.11.6 /opt/istio
echo 'export ISTIO_HOME=/opt/istio' >> /etc/profile
echo 'export PATH=$PATH:$ISTIO_HOME/bin' >> /etc/profile
source /etc/profile
istioctl version

# ------------------------------------------
# 8）安装ingress-nginx
# ------------------------------------------
kubectl apply -f ~/k8s-install/v1.23.3/ingress-nginx/deploy.yaml
kubectl get service -n ingress-nginx
kubectl get pods --namespace=ingress-nginx
