<?php
/**
 * Apply LAPORTE Theme CSS to BookStack
 *
 * This script reads the styles.css from the LAPORTE theme
 * and applies it to BookStack's app-custom-head setting.
 *
 * Run from the container:
 * php /config/setup/apply-theme-css.php
 */

// Define path to CSS file
$cssFile = dirname(__FILE__) . '/templates/laporte-custom-head.html';

if (!file_exists($cssFile)) {
    echo "Error: CSS file not found at: $cssFile\n";
    exit(1);
}

$cssContent = file_get_contents($cssFile);

if (empty($cssContent)) {
    echo "Error: CSS file is empty\n";
    exit(1);
}

// Connect to database using environment variables
$dbHost = getenv('DB_HOST') ?: 'db';
$dbName = getenv('DB_DATABASE') ?: getenv('DB_NAME') ?: 'bookstack';
$dbUser = getenv('DB_USERNAME') ?: getenv('DB_USER') ?: 'bookstack_user';
$dbPass = getenv('DB_PASSWORD') ?: '';

try {
    $pdo = new PDO(
        "mysql:host=$dbHost;dbname=$dbName;charset=utf8mb4",
        $dbUser,
        $dbPass
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    echo "Database connection failed: " . $e->getMessage() . "\n";
    exit(1);
}

// Update the setting
$stmt = $pdo->prepare("UPDATE settings SET value = ? WHERE setting_key = 'app-custom-head'");
$result = $stmt->execute([$cssContent]);

if ($result) {
    echo "Successfully applied LAPORTE theme CSS to BookStack!\n";
    echo "CSS length: " . strlen($cssContent) . " bytes\n";
} else {
    echo "Failed to update setting\n";
    exit(1);
}
