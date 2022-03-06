#!/bin/bash
#

cat > /mnt/extra/management.xml <<EOF
<network>
  <name>management</name>
  <forward mode='nat'/>
  <bridge name='virbr255' stp='on' delay='0'/>
  <mac address='52:54:00:8a:8b:cd'/>
  <ip address='192.168.255.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.255.2' end='192.168.255.254'/>
      <host mac='52:54:00:8a:8b:c1' name='netsim' ip='192.168.255.100'/>
    </dhcp>
  </ip>
</network>
EOF

virsh net-define /mnt/extra/management.xml && virsh net-autostart management && virsh net-start management && virsh net-list --all

./kvm-install-vm create -c 48 -m 200704 -d 800 -t ubuntu2004 -f host-passthrough -k /root/.ssh/id_rsa.pub -l /mnt/extra/virt/images -L /mnt/extra/virt/vms -b virbr255 -T US/Eastern -M 52:54:00:8a:8b:c1 netsim

virsh list --all && brctl show && virsh net-list --all

sleep 90

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "uname -a && sudo ip a"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim 'echo "root:gprm8350" | sudo chpasswd'
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim 'echo "ubuntu:kyax7344" | sudo chpasswd' 
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config" 
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo systemctl restart sshd"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo rm -rf /root/.ssh/authorized_keys"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "cat << EOF | sudo tee /etc/modprobe.d/qemu-system-x86.conf
options kvm_intel nested=1
EOF"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "cat << EOF | sudo tee /etc/sysctl.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv6.conf.all.forwarding=1
net.mpls.conf.lo.input=1
net.mpls.conf.ens3.input=1
net.mpls.platform_labels=100000
net.ipv4.tcp_l3mdev_accept=1
net.ipv4.udp_l3mdev_accept=1
EOF"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "cat << EOF | sudo tee /etc/sysctl.d/60-lxd-production.conf
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=1048576
vm.max_map_count=262144
kernel.dmesg_restrict=1
net.ipv4.neigh.default.gc_thresh3=8192
net.ipv6.neigh.default.gc_thresh3=8192
net.core.bpf_jit_limit=3000000000
kernel.keys.maxkeys=2000
kernel.keys.maxbytes=2000000
EOF"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "cat << EOF | sudo tee /etc/modules-load.d/modules.conf
mpls_router
mpls_gso
mpls_iptunnel
EOF"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo apt update -y && sudo apt install vim git wget net-tools locate -y"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo apt update && sudo apt upgrade -y"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo DEBIAN_FRONTEND=noninteractive apt-get install linux-generic-hwe-20.04 --install-recommends -y"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo apt autoremove -y && sudo apt --fix-broken install -y"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo apt-get install genisoimage libguestfs-tools libosinfo-bin virtinst qemu qemu-kvm qemu-system git vim net-tools wget curl bash-completion python3-pip libvirt-daemon-system virt-manager bridge-utils libnss-libvirt libvirt-clients osinfo-db-tools intltool sshpass ovmf genometools virt-top haveged -y"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo sed -i 's/hosts:          files dns/hosts:          files libvirt libvirt_guest dns/' /etc/nsswitch.conf && sudo lsmod | grep kvm"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo usermod -aG libvirt ubuntu && sudo adduser ubuntu libvirt-qemu && sudo adduser ubuntu kvm && sudo adduser ubuntu libvirt-dnsmasq && echo 0 | sudo tee /sys/module/kvm/parameters/halt_poll_ns"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo sed -i 's/0770/0777/' /etc/libvirt/libvirtd.conf"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo DEBIAN_FRONTEND=noninteractive apt install cinnamon-desktop-environment --install-recommends -y"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo DEBIAN_FRONTEND=noninteractive apt install xrdp --install-recommends -y"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo ufw allow from any to any port 3389 proto tcp"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo systemctl enable --now xrdp"
ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo systemctl set-default graphical.target"

ssh -o "StrictHostKeyChecking=no" ubuntu@netsim "sudo reboot"
