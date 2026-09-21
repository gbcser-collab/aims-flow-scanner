<?php
declare(strict_types=1);

require __DIR__ . '/smart_rules.php';

function fail(string $message): never {
    fwrite(STDERR, "FAIL: $message\n");
    exit(1);
}

$input = 'Stražská 483, 348 02 Bor u Tachova';
$candidates = aims_geocode_address_candidates($input);

if (($candidates[0] ?? null) !== $input) {
    fail('original address must stay first');
}
if (!in_array('Stražská 483, Bor u Tachova', $candidates, true)) {
    fail('postal-code-free fallback missing');
}
$asciiFound = false;
foreach ($candidates as $candidate) {
    if (stripos($candidate, 'Strazska 483') !== false &&
        stripos($candidate, 'Bor u Tachova') !== false) {
        $asciiFound = true;
        break;
    }
}
if (!$asciiFound) {
    fail('accentless street+city fallback missing');
}
foreach ($candidates as $candidate) {
    if (trim($candidate) === 'Bor u Tachova') {
        fail('unsafe city-only fallback must never be emitted');
    }
}
if (count($candidates) !== count(array_unique($candidates))) {
    fail('candidate list must be deduplicated');
}

echo "PASS: safe geocode fallback candidates\n";
