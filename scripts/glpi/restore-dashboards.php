<?php
// Recrée les tableaux de bord par défaut de GLPI qui ont été supprimés (avec leurs cartes)
chdir('/var/www/glpi');
require_once '/var/www/glpi/vendor/autoload.php';
$kernel = new \Glpi\Kernel\Kernel();
$kernel->boot();
global $DB;
use Glpi\Dashboard\Dashboard;
$restored = 0;
foreach (Dashboard::getDefaults() as $def) {
    $exists = $DB->request(['FROM' => 'glpi_dashboards_dashboards', 'WHERE' => ['key' => $def['key']]])->count();
    if ($exists) { echo "déjà présent : {$def['key']}\n"; continue; }
    $DB->insert('glpi_dashboards_dashboards', ['key' => $def['key'], 'name' => $def['name'], 'context' => $def['context']]);
    $id = $DB->insertId();
    $n = 0;
    foreach ($def['items'] as $item) {
        $item['dashboards_dashboards_id'] = $id;
        $item['card_options'] = json_encode($item['card_options']);
        $DB->insert('glpi_dashboards_items', $item);
        $n++;
    }
    echo "recréé : {$def['key']} ({$def['name']}) avec $n cartes\n";
    $restored++;
}
echo "total recréés : $restored\n";
