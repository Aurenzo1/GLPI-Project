# Légende des captures d'écran — Projet GLPI sécurisé

Dossier : `GLPI-Project`. Le préfixe numérique de chaque fichier correspond à l'étape du guide de montage et à la ligne du cahier de recettes. Deux machines virtuelles VirtualBox : **srv-glpi** (Ubuntu Server 24.04, 192.168.1.10, VPN 10.8.0.1) et **pc-client** (Xubuntu 24.04, 192.168.1.20, VPN 10.8.0.2).

> ⚠️ **Une capture est à refaire** : `4-FW-Client.png` (voir étape 04). Une autre est à améliorer : `9-GLPI-Mail-Actions.png`.

---

## Étape 01 — Environnement réseau (priorité très haute)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `1-NAT GLPI-Server.png` | VirtualBox, Outils → Réseau → Réseaux NAT | Le réseau `glpi-net`, préfixe 192.168.1.0/24, DHCP activé, IPv6 désactivé | Les deux VM partagent un réseau privé isolé, simulant le LAN de l'entreprise |
| `1-IP-Ping Client.png` | Terminal pc-client | `ip -br a` : enp0s3 en 192.168.1.20 (LAN) et wg0 en 10.8.0.2 (VPN). `ping 192.168.1.10` : 100 % de perte | Le client a bien ses deux adresses. Le ping LAN échoue **parce que l'IPS Suricata le bloque** (règle locale, voir étape 06), ce n'est pas une panne réseau |

## Étape 02 — Serveur GLPI (priorité haute)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `2-Dashboard-GLPI.png` | Firefox sur pc-client, accueil GLPI | Tableau de bord « Central » : 1 ordinateur, 1,8 K logiciels, 4 utilisateurs, 2 tickets | GLPI installé, base peuplée par l'inventaire et le collecteur, aucun bandeau d'alerte (comptes par défaut changés, dossier install supprimé) |
| `2-GLPI-Version.png` | Configuration → Générale → Système | « GLPI 11.0.8 » | Version installée : dernière stable, qui apporte la 2FA native |
| `2-Authenticator-GLPI.png` | Firefox, `glpi.local/MFA/Prompt` | Écran de saisie du code à six chiffres après le mot de passe | **Relève en réalité de l'étape 05** : la double authentification est active et exigée à la connexion. À classer avec `5-MFA-GLPI.png` |

## Étape 03 — VPN WireGuard (priorité haute)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `3-VPN-Client.png` | Terminal pc-client, `sudo wg show` | Interface wg0, pair = clé publique du serveur, endpoint 192.168.1.10:51820, clé pré-partagée (masquée), handshake il y a 35 s, keepalive 25 s | Le tunnel est établi côté client, avec PSK en plus des clés publiques (réponse au « sécuriser le tunnel ») |
| `3-VPN-Server.png` | Terminal srv-glpi, `sudo wg show` + config avec clés masquées | Port d'écoute 51820, pair = client, allowed ips 10.8.0.2/32, handshake récent ; fichier wg0.conf avec PrivateKey/PresharedKey remplacées par **** | Même tunnel vu du serveur ; le pair n'est autorisé que sur sa seule adresse VPN ; les secrets ne sont pas exposés dans le rapport |

## Étape 04 — Pare-feu (priorité haute)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `4-FW-Server.png` | Terminal srv-glpi, `sudo ufw status verbose` | Status active, default deny incoming ; seules règles ALLOW : 51820/udp (WireGuard) et 443, 80, 22 **on wg0** | Rien n'entre par le LAN sauf le tunnel ; GLPI et SSH ne sont joignables qu'à travers le VPN |
| `4-FW-Client.png` ⚠️ **À REFAIRE** | Terminal pc-client, `nmap` sur 192.168.1.10 puis 10.8.0.1 | Les ports 22/80/443 apparaissent **open** dans les deux cas | Capture prise à 11:44, pendant un défaut temporaire : en mode NFQUEUE par défaut, le verdict « accept » de Suricata faisait sortir les paquets de la chaîne iptables avant les règles UFW. Corrigé depuis (mode « repeat » avec marquage des paquets). **Refaire la capture** avec `./demo-vpn.sh` sur pc-client : attendu **filtered** sur 192.168.1.10 et **open** sur 10.8.0.1. Le défaut et sa correction méritent un paragraphe dans le rapport |

## Étape 05 — Double authentification (priorité haute)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `5-MFA-GLPI.png` | Configuration → Générale → Sécurité | « Forcer 2FA » activé, période de grâce 2 jours | La 2FA (TOTP, application d'authentification) est obligatoire pour tous les comptes |
| `2-Authenticator-GLPI.png` | Firefox, connexion | Invite du code à six chiffres | La 2FA est effectivement demandée à chaque connexion |

Remarque pour le rapport : la MFA porte sur GLPI. Elle n'a pas été mise sur SSH du serveur (choix documenté).

## Étape 06 — IPS Suricata (priorité haute)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `6-Suricata-Conf.png` | Terminal srv-glpi, `sudo suricata -T -c /etc/suricata/suricata.yaml` | Suricata 8.0.6, « Configuration provided was successfully loaded » | La configuration (HOME_NET = LAN + VPN, règles Emerging Threats + règles locales) est valide ; réponse au « attention aux fichiers de configuration » |
| `6-Suricata-NFQUEUE.png` | Terminal srv-glpi, `sudo iptables -L ufw-before-input` | Règle n° 2 : NFQUEUE num 0 bypass, placée avant l'ACCEPT des connexions établies | Tout le trafic entrant passe par Suricata en mode IPS (blocage possible), avant les règles UFW. Depuis la correction de l'étape 04, cette règle porte en plus un filtre de marquage (`mark ! 0x1`) ; capture optionnelle à refaire |
| `6-Client-TO.png` | Terminal pc-client | `ping 10.8.0.1` : 100 % de perte ; `curl` sur `index.php?file=/etc/passwd` : timeout après 8 s | L'IPS **bloque** réellement : le ping (règle locale sid 9000003) et une tentative de lecture de `/etc/passwd` par le web (sid 9000002). Le trafic est inspecté déchiffré sur l'interface VPN |

Remarque pour le rapport : le site de test `testmynids.org` cité dans le guide est injoignable, il a été remplacé par trois règles locales signées « LAB » (journalisation SSH, blocage /etc/passwd, blocage ping).

## Étape 07 — Client et agent GLPI (priorité moyenne)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `7-GLPI-Inventaire.png` | Administration → Inventaire | « Activer l'inventaire » coché, options d'importation (volumes, logiciels, moniteurs, etc.), fréquence 24 h | L'inventaire natif de GLPI (à partir de la version 10, sans FusionInventory) est actif |
| `7-GLPI-Client.png` | Parc → Ordinateurs | Ligne `pc-client` : fabricant innotek GmbH, n° de série VirtualBox-…, Ubuntu 24.04.4 LTS, processeur détecté, dernière modification 10:31 | L'agent GLPI 1.19 installé sur le client a remonté son inventaire au serveur, à travers le VPN et en HTTPS avec vérification du certificat |

## Étape 08 — Contrôle à distance (priorité moyenne)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `8-GLPI-VNC.png` | Fiche Ordinateur pc-client → onglet Liens | « Prise en main VNC #1 : vnc://[IP]:5900 » | L'outil de contrôle à distance est intégré à GLPI : un lien externe qui remplace [IP] par l'adresse du poste et lance la prise en main depuis la fiche |
| `8-Client-VNC.png` | Terminal pc-client, `ss -ltnp` et `ufw status` | x11vnc écoute sur 10.8.0.2:5900 ; pare-feu du client : 22/tcp ouvert, 5900/tcp autorisé **sur wg0 uniquement** | Le serveur VNC n'est joignable qu'à travers le tunnel VPN, jamais depuis le LAN (l'écoute IPv6 visible est filtrée par UFW) |

## Étape 09 — Collecteur de mails (priorité moyenne)

| Fichier | Où | Ce qu'on voit | Ce que ça prouve |
|---|---|---|---|
| `9-GLPI-Mail.png` | Configuration → Collecteurs | Collecteur « Support par mail », actif, modifié le 2026-09-03 10:43 | GLPI relève une boîte IMAP locale (Postfix + Dovecot sur le serveur, compte `support`) |
| `9-GLPI-Mail-Actions.png` ⚠️ à améliorer | Configuration → Actions automatiques | Liste des actions (cartridge, consumable, software…) | La ligne utile, **mailgate**, n'est pas visible. Refaire la capture en recherchant « mailgate » : mode d'exécution CLI, fréquence 2 minutes, dernière exécution. Le bandeau d'avertissement en haut vient du cron système qui venait d'être mis en place |
| `9-GLPI-Tickets.png` | Assistance → Tickets | Tickets n° 1 « Bonjour, mon écran reste noir… » et n° 2 « Imprimante en panne - bureau 12 », statut Nouveau, demandeur `normal` | Deux mails envoyés à `support@` ont été transformés automatiquement en tickets, avec le bon demandeur (reconnu par son adresse d'expéditeur). Pour la source « E-Mail », ajouter la colonne Source ou ouvrir un ticket |

---

## Vidéo

`GLPI-Présentation.mp4` (2 min 30, muette) : démonstration enchaînée VPN → connexion 2FA → inventaire → lien VNC → mail vers ticket → attaque bloquée par l'IPS.

## Rappel des écarts assumés (à mentionner dans le rapport)

- Certificat HTTPS auto-signé (environnement de recette).
- Messagerie locale au lieu d'une boîte externe : aucune donnée réelle, conformément au cahier des charges.
- Suricata en NFQUEUE avec `--queue-bypass` : si l'IPS s'arrête, le trafic passe (choix de disponibilité) ; le mode « repeat » a dû être activé pour que les règles UFW restent appliquées après inspection.
- MFA sur GLPI, pas sur SSH.
- Site de test IDS remplacé par des règles locales.
- VirtualBox en mode dégradé (Hyper-V actif sur l'hôte) : 1 vCPU par VM, snapshots à froid uniquement.
