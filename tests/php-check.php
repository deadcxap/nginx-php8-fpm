<?php
declare(strict_types=1);

$required = [
    'amqp', 'bcmath', 'brotli', 'ctype', 'curl', 'dom', 'exif', 'fileinfo',
    'gd', 'gettext', 'iconv', 'igbinary', 'imagick', 'imap', 'intl', 'ldap',
    'mbstring', 'memcached', 'mongodb', 'msgpack', 'mysqli', 'openssl',
    'pdo_mysql', 'pdo_pgsql', 'pdo_sqlite', 'pgsql', 'redis', 'soap',
    'sockets', 'sodium', 'xml', 'zip', 'Zend OPcache',
];
$missing = array_values(array_filter($required, fn ($name) => !extension_loaded($name)));
if ($missing) {
    throw new RuntimeException('Missing PHP extensions: ' . implode(', ', $missing));
}
foreach (['JPEG Support', 'FreeType Support', 'WebP Support'] as $feature) {
    if (empty(gd_info()[$feature])) {
        throw new RuntimeException('GD missing ' . $feature);
    }
}
$image = new Imagick();
$image->newImage(2, 2, 'white', 'png');
if (strlen($image->getImageBlob()) === 0) {
    throw new RuntimeException('Imagick could not encode a PNG.');
}
if (brotli_uncompress(brotli_compress('smoke test')) !== 'smoke test') {
    throw new RuntimeException('Brotli round trip failed.');
}
$database = new PDO('sqlite::memory:');
if ((int) $database->query('SELECT 42')->fetchColumn() !== 42) {
    throw new RuntimeException('PDO SQLite failed.');
}
echo "PHP extensions and native libraries OK\n";
