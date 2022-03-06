# Copyright 2012-2021 Canonical Ltd.  This software is licensed under the
# GNU Affero General Public License version 3 (see the file LICENSE).

# README FIRST
# You need a reasonably powerful machine, 4 or more cores with 32 GB of RAM and 500GB of free disk space. Assumes a fresh install of Ubuntu server (20.04 or higher) on the machine.
# Note: this tutorial has not been tested on versions prior to 20.04.

# lxd / maas issue. either upgrade lxd or maas to 3.1
sudo snap switch --channel=latest/stable lxd
sudo snap install lxd
sudo snap refresh lxd
sudo snap install jq
sudo snap install kubectl --classic
sudo snap install --channel=3.1/edge maas
sudo snap install --channel=3.1/edge maas-test-db

# clone the git repository
cd ~
git clone https://github.com/vpasias/maas-lxd.git

# get local interface name (this assumes a single default route is present)
export INTERFACE=$(ip route | grep default | cut -d ' ' -f 5)
export IP_ADDRESS=$(ip -4 addr show dev $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p
sudo iptables -t nat -A POSTROUTING -o $INTERFACE -j SNAT --to $IP_ADDRESS
#TODO inbound port forwarding/load balancing
# Persist NAT configuration
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt-get install iptables-persistent -y
# LXD init
sudo cat /home/ubuntu/maas-lxd/lxd.conf | lxd init --preseed
# verify LXD network config
lxc network show lxdbr0
# Wait for LXD to be ready
lxd waitready
# Initialise MAAS
sudo maas init region+rack --database-uri maas-test-db:/// --maas-url http://${IP_ADDRESS}:5240/MAAS
sleep 60
# Create MAAS admin and grab API key
sudo maas createadmin --username admin --password admin --email admin
export APIKEY=$(sudo maas apikey --username admin)
# MAAS admin login
maas login admin 'http://localhost:5240/MAAS/' $APIKEY
# Configure MAAS networking (set gateways, vlans, DHCP on etc)
export SUBNET=10.10.10.0/24
export FABRIC_ID=$(maas admin subnet read "$SUBNET" | jq -r ".vlan.fabric_id")
export VLAN_TAG=$(maas admin subnet read "$SUBNET" | jq -r ".vlan.vid")
export PRIMARY_RACK=$(maas admin rack-controllers read | jq -r ".[] | .system_id")
maas admin subnet update $SUBNET gateway_ip=10.10.10.1
maas admin ipranges create type=dynamic start_ip=10.10.10.200 end_ip=10.10.10.254
maas admin vlan update $FABRIC_ID $VLAN_TAG dhcp_on=True primary_rack=$PRIMARY_RACK
maas admin maas set-config name=upstream_dns value=8.8.8.8
# Add LXD as a VM host for MAAS and capture the VM_HOST_ID
export VM_HOST_ID=$(maas admin vm-hosts create  password=password  type=lxd power_address=https://${IP_ADDRESS}:8443 project=maas | jq '.id')

# allow high CPU oversubscription so all VMs can use all cores
maas admin vm-host update $VM_HOST_ID cpu_over_commit_ratio=4

# create tags for MAAS
maas admin tags create name=juju-controller comment='This tag should to machines that will be used as juju controllers'
maas admin tags create name=node comment='This tag should to machines that will be used as hosts'

### creating VMs for Juju controller and nodes

# add a VM for the juju controller with minimal memory
# maas admin vm-host compose $VM_HOST_ID cores=4 memory=4096 architecture="amd64/generic" storage="main:16(pool1)" hostname="juju-controller"

## Create 7 host machines and tag them with "node"
for ID in 1 2 3 4 5 6 7
do
    maas admin vm-host compose $VM_HOST_ID cores=6 memory=16384 architecture="amd64/generic" storage="main:25(pool1),ceph:100(pool1)" hostname="node-${ID}"
    SYSID=$(maas admin machines read | jq -r --arg MACHINE "node-${ID}" '.[] 
    | select(."hostname"==$MACHINE) 
    | .["system_id"]' | tr -d '"')
    maas admin tag update-nodes "node" add=$SYSID
done


### Juju setup (note, this section requires manual intervention)
cd ~
sudo snap install juju --classic
sed -i "s/IP_ADDRESS/$IP_ADDRESS/" /home/ubuntu/maas-lxd/maas-cloud.yaml
juju add-cloud --local maas-cloud /home/ubuntu/maas-lxd/maas-cloud.yaml
MAAS_APIKEY=$(sudo maas apikey --username admin)
sed -i 's/{{ maas_admin_apikey }}/'${MAAS_APIKEY}'/g' /home/ubuntu/maas-lxd/credentials.yaml
juju add-credential maas-cloud -f /home/ubuntu/maas-lxd/credentials.yaml
juju clouds --local
juju credentials

# fire up the juju gui to view the fun
# if it's a remote machine, you can use an SSH tunnel to get access to it:
# e.g. ssh ubuntu@x.x.x.x -L8080:10.10.10.2:17070
# juju dashboard

### Kubernetes

# Deploy kubernetes-core with juju and re-use existing machines. 
# juju deploy kubernetes-core --map-machines=existing,0=0,1=1

# add the new kubernetes as a cloud to juju
# mkdir ~/.kube && juju scp kubernetes-master/0:/home/ubuntu/config ~/.kube/config

# add storage relations
# juju add-relation ceph-mon:admin kubernetes-master
# juju add-relation ceph-mon:client kubernetes-master

# add k8s to juju (choose option 1, client only)
# juju add-k8s my-k8s

#juju bootstrap my-k8s
#juju controllers

# add a kubernetes-worker
# juju add-unit kubernetes-worker --to 2

### Deploy a test application on K8s cluster

# Create a model in juju, which creates a namespace in K8s
# juju add-model hello-kubecon

# Deploy the charm "hello-kubecon", and set a hostname for the ingress
# juju deploy hello-kubecon --config juju-external-hostname=kubecon.test

# Deploy the ingress integrator - this is a helper to setup the ingress
# juju deploy nginx-ingress-integrator ingress

# trust the ingress (it needs cluster credentials to make changes)
# juju trust ingress --scope=cluster

# Relate our app to the ingress - this causes the ingress to be setup
# juju relate hello-kubecon ingress

# Explore the setup 
# kubectl describe ingress -n hello-kubecon
# kubectl get svc -n hello-kubecon
# kubectl describe svc hello-kubecon-service -n hello-kubecon
# kubectl get pods -n hello-kubecon

# Lastly, in order to be able to reach the service from outside our host machine,
# we can use port forwarding. Replace 10.10.10.5 with the IP seen on the ingress.
# sudo iptables -t nat -A PREROUTING -p tcp -i enp6s0 --dport 8000 -j DNAT --to-destination 10.10.10.5:80
# if you want to persist this, run sudo dpkg-reconfigure iptables-persistent
# Now you should be able to open a browser and navigate to http://$IP_ADDRESS:8000

# scale our kubernetes cluster - find a machine 
# Avoid kubernetes-master or existing kubernetes-worker machines
# https://discourse.charmhub.io/t/scaling-applications/1075
# juju switch maas-cloud-default
# juju status

# add another kubecon unit
# juju switch my-k8s
# juju add-unit -n 1 hello-kubecon
# juju status

# what happened to the ingress?
# kubectl get ingress -n hello-kubecon

# scale down hello-kubecon
# juju remove-unit --num-units 1  hello-kubecon

# scaledown kubernetes
# juju switch maas-cloud-default 
# juju remove-unit kubernetes-worker/1
# juju status

# if you want to test destroying your hello-kubecon:
# juju switch my-k8s
# juju destroy-model hello-kubecon --release-storage

# if you want to destroy your kubenetes controller for juju
# juju switch maas-cloud-default
# juju destroy-controller my-k8s

# if you want to remove your k8s cluster:
# juju switch maas-cloud-default
# juju remove-application kubernetes-master kubernetes-worker etcd flannel easyrsa

# if you want to remove ceph
# juju switch maas-cloud-default
# juju remove-application ceph-mon ceph-osd

# To clean up everything:
# juju destroy-controller -y --destroy-all-models --destroy-storage maas-cloud-default
# And the machines created in MAAS can be deleted easily in the MAAS GUI.

### Reference materials notes
# https://jaas.ai/ceph-base
# https://jaas.ai/canonical-kubernetes/bundle/471
# https://medium.com/swlh/kubernetes-external-ip-service-type-5e5e9ad62fcd
# https://charmhub.io/nginx-ingress-integrator
# https://drive.google.com/file/d/1estQna40vz4uS5tBd9CvKdILdwAmcNFH/view - hello-kubecon
# https://ubuntu.com/kubernetes/docs/troubleshooting - troubleshooting
# https://juju.is/blog/deploying-mattermost-and-kubeflow-on-kubernetes-with-juju-2-9

### END
