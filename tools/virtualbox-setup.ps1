# Configuration VirtualBox du laboratoire (rejouable). Hote Windows 11, VirtualBox 7.2.
# Prerequis : deux VM creees "srv-glpi" (Ubuntu Server 24.04, 4 Go) et "pc-client" (Xubuntu 24.04, 2 Go), eteintes.
$vbm = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# 1 vCPU par VM : avec Hyper-V actif sur l'hote, 2 vCPU provoquaient un plantage du noyau invite
& $vbm modifyvm srv-glpi  --cpus 1 --pae on --paravirt-provider default --nic-type1 virtio --nic1 natnetwork --nat-network1 glpi-net
& $vbm modifyvm pc-client --cpus 1 --pae on --paravirt-provider default --nic-type1 virtio --nic1 natnetwork --nat-network1 glpi-net

# Reseau NAT commun (LAN simule)
& $vbm natnetwork add --netname glpi-net --network "192.168.1.0/24" --enable --dhcp on
& $vbm natnetwork start --netname glpi-net

# Le relais DNS de VirtualBox ne repondait pas : on distribue de vrais resolveurs par DHCP (option 6)
& $vbm dhcpserver modify --network=glpi-net --set-opt=6 "1.1.1.1 9.9.9.9"

# Adresses fixes (remplacer les MAC par celles de vos VM : VBoxManage showvminfo <vm> | findstr MAC)
& $vbm dhcpserver modify --network=glpi-net --mac-address=080027FB88DB --fixed-address=192.168.1.10   # srv-glpi
& $vbm dhcpserver modify --network=glpi-net --mac-address=0800272D5858 --fixed-address=192.168.1.20   # pc-client
& $vbm dhcpserver restart --network=glpi-net

# Acces d'administration depuis l'hote : SSH vers le client uniquement (le serveur n'est joignable que par le VPN)
& $vbm natnetwork modify --netname glpi-net --port-forward-4 "ssh-cli:tcp:[]:2223:[192.168.1.20]:22"

# Snapshots : toujours VM eteinte (les snapshots a chaud sont inutilisables sous Hyper-V)
# & $vbm snapshot srv-glpi take "01-base-installee"
