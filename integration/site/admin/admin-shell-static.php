<?php
declare(strict_types=1);

function aims_render_admin_shell(): void {
    $file = strtolower(basename((string)($_SERVER['SCRIPT_NAME'] ?? '')));
    $family = ['partner.php'=>'partners.php','freight.php'=>'index.php','freights.php'=>'index.php',
      'order-details.php'=>'index.php','aims-flow-job-stops.php'=>'aims-flow.php',
      'mailbox-setup.php'=>'automation.php','message.php'=>'messages.php','setup.php'=>'home.php'];
    $active = $family[$file] ?? $file;
    $groups = [
      'MUNKATÉR'=>[
        ['home.php','⌂','Áttekintés'],['index.php','↔','Fuvarok'],
        ['order-ai.php','↑','PDF-beolvasás'],['aims-fleet.php','▣','Flotta és térkép'],
        ['aims-flow-workspace.php','◈','FLOW-központ'],['notifications.php','◌','Jelzések']],
      'FUVARIRÁNYÍTÁS'=>[
        ['freights.php','+','Árajánlatkérés'],['control-tower.php','◎','Control Tower'],
        ['dispatch-optimizer.php','⇄','Diszpécser'],['incidents.php','!','Incidensek'],
        ['aims-flow.php','◇','FLOW-eszközök'],['aims-flow-driver-access.php','◉','Sofőr-hozzáférések'],['../flow/app/','↓','Alkalmazás és belépés']],
      'IRODA'=>[
        ['partners.php','♧','Partnerek'],['billing-ready.php','▤','Számlázási kapu'],
        ['messages.php','≡','Üzenetnapló'],['automation.php','✉','E-mail-bot'],['autopilot.php','↻','Autopilot']],
      'RIPORTOK'=>[
        ['aims-flow-mileage.php','€','Kilométer és árrés'],['aims-flow-monthly-report.php','▦','Időszaki riport'],['aims-flow-eco.php','◷','ECO-elemzés'],
        ['foreign-stay-report.php','◴','Külföldi tartózkodás'],['analytics.php','▥','Webes analitika']],
    ];
    $h=static fn($s)=>htmlspecialchars((string)$s,ENT_QUOTES,'UTF-8');
?>
<a class="aims-skip" href="#aimsMainStart">Ugrás a tartalomra</a>
<aside id="aimsUnifiedShell" class="home6-side" aria-label="Adminmenü">
  <a class="home6-brand aims-shell-brand" href="home.php"><img src="assets/aims-logo.png" alt="Logistic-AIMS"><span>ADMINISZTRÁCIÓ</span></a>
  <nav class="aims-nav-groups" aria-label="Adminmodulok">
  <?php foreach($groups as $label=>$links): ?>
    <section class="aims-nav-group"><h2><?=$h($label)?></h2>
    <?php foreach($links as [$href,$icon,$title]):$isActive=$file==='freights.php'?$href==='freights.php':$active===$href;?>
      <a href="<?=$h($href)?>" <?=$isActive?'class="active" aria-current="page"':''?>><i aria-hidden="true"><?=$icon?></i><span><?=$h($title)?></span><?php if($href==='notifications.php'):?><b class="home6-badge aims-nav-count" data-nav-count="notifications.php" hidden>0</b><?php endif;?></a>
    <?php endforeach;?></section>
  <?php endforeach;?>
  </nav>
  <div class="home6-sidefoot aims-shell-foot"><strong data-aims-system-health>Állapot ellenőrzése…</strong><br><span data-aims-system-health-detail>GPS és értesítések</span><a class="aims-exit" href="logout.php">Kilépés ↗</a></div>
</aside>
<header id="aimsUnifiedTop" class="home6-top">
  <button type="button" class="aims-menu-toggle" aria-controls="aimsUnifiedShell" aria-expanded="false" aria-label="Adminmenü megnyitása">☰</button>
  <form class="home6-search aims-global-search" action="search.php" method="get" role="search"><label class="aims-sr-only" for="aimsGlobalSearch">Keresés a rendszerben</label><input id="aimsGlobalSearch" name="q" type="search" placeholder="Fuvar, rendszám, partner…" autocomplete="off"><button class="aims-search-submit" aria-label="Keresés">↵</button></form>
  <div class="home6-topright aims-top-actions">
    <a class="aims-top-import" href="order-ai.php">↑ <span>PDF-beolvasás</span></a>
    <details class="aims-notify" id="aimsNotify"><summary class="home6-iconbtn" aria-label="Élő jelzések"><span class="aims-notify-bell">◌</span><b class="aims-notify-badge" data-notify-badge hidden>0</b></summary>
      <div class="aims-notify-menu"><div class="aims-notify-head"><div><b>Élő jelzések</b><small data-notify-health>Kapcsolódás…</small></div><a href="notifications.php">Összes →</a></div><div class="aims-notify-items" data-notify-items><div class="aims-notify-empty">Betöltés…</div></div><div class="aims-notify-foot" data-notify-foot></div></div>
    </details>
    <div class="home6-profile aims-admin-profile"><span class="home6-avatar">A</span><div><b>Admin</b><small>Logistic-AIMS</small></div></div>
  </div>
</header>
<div id="aimsMainStart" tabindex="-1"></div>
<?php }
