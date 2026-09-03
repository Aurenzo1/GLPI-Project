#!/bin/bash
# Plan 7 (serveur) : ce que Suricata a bloque
echo ">>> Etat de Suricata : $(systemctl is-active suricata)"
sudo jq -r "select(.alert.signature_id>=9000001) | \"\(.timestamp[11:19])  \(.src_ip) -> \(.dest_ip)  \(.alert.action | ascii_upcase)  \(.alert.signature)\"" /var/log/suricata/eve.json | tail -n 8
