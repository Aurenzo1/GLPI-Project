#!/bin/bash
# Plan 7 (client) : attaque bloquee par l IPS
echo ">>> Requete web normale vers le serveur"
curl -s -o /dev/null -w "reponse HTTP %{http_code}\n" --max-time 8 http://10.8.0.1/
echo; echo ">>> Tentative de lecture de /etc/passwd via le site (attendu : bloquee, delai depasse)"
curl --max-time 8 "http://10.8.0.1/index.php?file=/etc/passwd" || echo "-> bloque par Suricata (timeout)"
echo; echo ">>> Ping vers le serveur (attendu : bloque)"
ping -c 3 -W 2 10.8.0.1 | tail -n 2
