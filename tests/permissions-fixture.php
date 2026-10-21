<?php
declare(strict_types=1);

$file = __DIR__ . '/writable/from-php.txt';
$directory = __DIR__ . '/writable/from-php-dir';
if (file_exists($file)) {
    unlink($file);
}
if (is_dir($directory)) {
    rmdir($directory);
}
if (file_put_contents($file, 'written-by-php') === false || !mkdir($directory, 0777)) {
    throw new RuntimeException('PHP cannot write to the mounted application directory.');
}
clearstatcache();
header('Content-Type: application/json');
echo json_encode([
    'uid' => posix_geteuid(),
    'gid' => posix_getegid(),
    'umask' => sprintf('%03o', umask()),
    'file_uid' => fileowner($file),
    'file_gid' => filegroup($file),
    'file_mode' => sprintf('%04o', fileperms($file) & 0777),
    'directory_mode' => sprintf('%04o', fileperms($directory) & 0777),
]);
