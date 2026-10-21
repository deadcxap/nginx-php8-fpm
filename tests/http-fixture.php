<?php
header('Content-Type: application/json');
echo json_encode([
    'ok' => true,
    'memory_limit' => ini_get('memory_limit'),
    'post_max_size' => ini_get('post_max_size'),
    'upload_max_filesize' => ini_get('upload_max_filesize'),
    'timezone' => date_default_timezone_get(),
], JSON_UNESCAPED_SLASHES);
