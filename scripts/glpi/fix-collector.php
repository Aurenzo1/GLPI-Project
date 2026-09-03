<?php
// Chiffre le mot de passe du collecteur avec la clé GLPI et le stocke correctement
chdir('/var/www/glpi');
require_once '/var/www/glpi/vendor/autoload.php';
$kernel = new \Glpi\Kernel\Kernel();
$kernel->boot();
$pass = getenv('MP');
$mc = new MailCollector();
if (!$mc->getFromDBByCrit(['name' => 'Support par mail'])) { fwrite(STDERR, "collecteur introuvable\n"); exit(1); }
$ok = $mc->update(['id' => $mc->getID(), 'passwd' => $pass, 'host' => '{localhost:143/imap/notls}INBOX', 'login' => 'support', 'is_active' => 1]);
echo "update: " . ($ok ? "OK" : "ECHEC") . "\n";
$mc->getFromDB($mc->getID());
echo "longueur passwd stocke: " . strlen($mc->fields['passwd']) . "\n";
try { $mc->connect(); echo "connexion IMAP via GLPI: OK\n"; } catch (\Throwable $e) { echo "connexion IMAP via GLPI: " . $e->getMessage() . "\n"; }
