#!/bin/bash
# Plan 2 (client) : acces uniquement par le VPN
echo ">>> Tunnel WireGuard"
sudo wg show
echo; echo ">>> Ports du serveur vus depuis le LAN (192.168.1.10)"
nmap -Pn -p 22,80,443 192.168.1.10 | grep -E "^[0-9]+/tcp"
echo; echo ">>> Ports du serveur vus a travers le VPN (10.8.0.1)"
nmap -Pn -p 22,80,443 10.8.0.1 | grep -E "^[0-9]+/tcp"
