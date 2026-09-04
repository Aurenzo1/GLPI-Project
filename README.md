# Système de ticketing sécurisé — infrastructure GLPI

Réponse au cahier de recettes du projet « Système de ticketing sécurisé » (référence amont CDC-TICKETING-SEC-001).
Deux machines Ubuntu, un serveur GLPI joignable uniquement à travers un tunnel VPN, une double authentification,
un IPS en mode blocage, l'inventaire automatique du poste client, la prise en main à distance et la création de
tickets par mail.

## Architecture

```
 Hôte Windows 11 (VirtualBox 7.2)
 └── Réseau NAT "glpi-net" 192.168.1.0/24  (LAN simulé, DHCP VirtualBox, DNS 1.1.1.1 / 9.9.9.9)
      ├── srv-glpi   192.168.1.10   Ubuntu Server 24.04 · 1 vCPU · 4 Go
      │     GLPI 11 (Apache/PHP/MariaDB, HTTPS) · WireGuard 10.8.0.1 · UFW · fail2ban
      │     Suricata 8 (IPS NFQUEUE) · Postfix + Dovecot (boîte support) · collecteur GLPI
      └── pc-client  192.168.1.20   Xubuntu 24.04 · 1 vCPU · 2 Go
            WireGuard 10.8.0.2 · agent GLPI 1.19 · x11vnc (VPN seulement) · UFW
      Tunnel WireGuard 10.8.0.0/24 : seul chemin vers GLPI (443), SSH (22) et VNC (5900)
```

## Correspondance avec le cahier de recettes

| Fonctionnalité | Priorité | Réalisation | Où dans le dépôt |
|---|---|---|---|
| Environnement réseau, 2 machines | Très haute | VirtualBox, réseau NAT glpi-net, adresses fixes | `tools/virtualbox-setup.ps1` |
| Serveur GLPI sur Ubuntu Server | Haute | GLPI 11.0.8, HTTPS, racine web `public/`, comptes par défaut remplacés | `scripts/serveur/etape02-glpi.sh`, `config/serveur/apache2/` |
| VPN sécurisé | Haute | WireGuard avec clé pré-partagée, AllowedIPs restreints | `config/serveur/wireguard/`, `config/client/wireguard/` |
| Pare-feu : seul le VPN entre | Haute | UFW deny incoming, services ouverts sur wg0 uniquement, fail2ban | `config/serveur/ufw/` |
| Double authentification | Haute | 2FA TOTP native GLPI 11, forcée pour tous | `config/serveur/glpi-config-appliquee.txt` |
| IPS Suricata | Haute | Suricata 8 en NFQUEUE mode repeat, règles ET Open + règles locales | `scripts/serveur/etape06-suricata.sh`, `config/serveur/suricata/` |
| Client Ubuntu + agent GLPI | Moyenne | Xubuntu, agent 1.19, inventaire natif via le VPN | `config/client/glpi-agent/` |
| Contrôle à distance | Moyenne | x11vnc sur l'adresse VPN, lien externe `vnc://[IP]:5900` dans GLPI | `config/client/systemd/x11vnc.service` |
| Collecte des mails → tickets | Moyenne | Postfix + Dovecot locaux, collecteur GLPI, cron mailgate | `scripts/serveur/etape09-mail.sh`, `config/serveur/mail/` |

## Contenu du dépôt

```
docs/                      guide de montage (HTML + PDF) et légende des captures d'écran
scripts/serveur/           installation rejouable : étape 02 (GLPI), 06 (Suricata), 06b (règles IPS), 09 (mails)
scripts/glpi/              outils PHP : chiffrement du mot de passe du collecteur, restauration des tableaux de bord
scripts/demo/              une commande par séquence de la vidéo de démonstration
config/serveur/            fichiers de configuration effectifs du serveur (secrets retirés)
config/client/             fichiers de configuration effectifs du client (secrets retirés)
tools/                     configuration VirtualBox rejouable, utilitaire d'injection clavier AZERTY
```

## Installation (ordre du guide)

1. **Machines et réseau** : créer les deux VM dans VirtualBox, puis exécuter `tools/virtualbox-setup.ps1`
   (adapter les adresses MAC). Installer Ubuntu Server 24.04 et Xubuntu 24.04 LTS.
2. **Serveur GLPI** : copier `scripts/serveur/etape02-glpi.sh` sur le serveur et le lancer comme service détaché :
   ```bash
   sudo systemd-run --unit=etape02 --collect /bin/bash ./etape02-glpi.sh
   sudo tail -f /var/log/etape02-glpi.log
   ```
   Le mot de passe de la base est généré et stocké dans `/root/glpi-db.env`. Changer ensuite les mots de passe
   des comptes `glpi`, `tech`, `normal`, `post-only`.
3. **VPN** : générer les clés sur chaque machine (`wg genkey | tee x.key | wg pubkey > x.pub`, `wg genpsk`),
   compléter les `wg0.conf.example` de `config/`, puis `systemctl enable --now wg-quick@wg0`.
4. **Pare-feu** : appliquer les règles de `config/serveur/ufw/ufw-status.txt` (voir le guide, étape 04),
   depuis la console de la VM, jamais depuis une session SSH sur le LAN.
5. **2FA** : `php bin/console config:set 2fa_enforced 1` puis `2fa_grace_days 2` ; enrôler les comptes.
6. **IPS** : `scripts/serveur/etape06-suricata.sh` puis `etape06b-tests.sh`. Attendre environ une minute après
   chaque redémarrage de Suricata (chargement de 52 000 règles sur 1 vCPU) avant de tester.
7. **Agent** : sur le client, installeur `glpi-agent-<version>-linux-installer.pl` avec
   `--server=https://glpi.local/front/inventory.php --ca-cert-file=/etc/glpi-agent/glpi.crt`.
   Activer l'inventaire : `php bin/console config:set --context=inventory enabled_inventory 1`.
8. **VNC** : `config/client/systemd/x11vnc.service`, règle UFW `allow in on wg0 to any port 5900 proto tcp`,
   lien externe GLPI `vnc://[IP]:5900` sur le type Ordinateur.
9. **Mails** : `scripts/serveur/etape09-mail.sh`, puis `scripts/glpi/fix-collector.php` pour stocker le mot de passe
   du collecteur au format chiffré de GLPI.

## Vérifications de recette (preuves)

Depuis le client : `scripts/demo/demo-vpn.sh` (ports filtrés par le LAN, ouverts par le VPN),
`scripts/demo/demo-ips.sh` (ping et requête `/etc/passwd` bloqués). Depuis le serveur : `demo-firewall.sh`,
`demo-mail.sh` (un mail devient un ticket), `demo-ips-log.sh` (événements « blocked » de Suricata).
La légende détaillée des captures est dans `docs/captures-legende.md`.

## Points d'attention et écarts assumés

- **Suricata et UFW** : en mode NFQUEUE par défaut, le verdict « accept » de Suricata fait sortir le paquet de la
  chaîne iptables avant les règles UFW, ce qui ouvrait le serveur depuis le LAN. Correction : `nfq: mode: repeat`
  avec marquage (`repeat-mark: 1`) et règle iptables `-m mark ! --mark 0x1/0x1 -j NFQUEUE`. Voir
  `config/serveur/suricata/suricata.yaml.diff` et `config/serveur/ufw/before.rules`.
- `--queue-bypass` : si Suricata s'arrête, le trafic passe (choix de disponibilité ; le retirer donne un
  comportement fermé en cas de panne).
- Certificat HTTPS auto-signé (environnement de recette) ; l'agent vérifie ce certificat au lieu de désactiver
  la vérification.
- Le site de test IDS `testmynids.org` étant injoignable, la preuve de blocage repose sur des règles locales
  (`config/serveur/suricata/local.rules`, signatures 9000001 à 9000003).
- La MFA porte sur GLPI ; elle n'a pas été ajoutée sur SSH du serveur.
- Aucune donnée réelle : messagerie locale et utilisateurs fictifs, conformément au cahier des charges.
- VirtualBox tourne en mode dégradé sur un hôte où Hyper-V est actif : 1 vCPU par VM, snapshots uniquement
  à froid.

## Secrets

Aucun secret n'est versionné (`.gitignore`). Sur les machines : `/root/glpi-db.env`, `/root/glpi-comptes.txt`,
`/root/mail-support.env` (serveur), `/root/vnc-mdp.txt` (client), clés WireGuard dans `/etc/wireguard/` (mode 600).
