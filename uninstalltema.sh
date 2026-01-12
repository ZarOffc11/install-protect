echo "🧹 Menghapus semua theme dan addon..."
cd /var/www/pterodactyl || exit 1

# Maintenance mode
php artisan down

# Ambil panel versi terbaru langsung dari GitHub Pterodactyl
curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv

# Set izin file dan cache
chmod -R 755 storage/* bootstrap/cache
composer install --no-dev --optimize-autoloader

php artisan view:clear
php artisan config:clear
php artisan migrate --seed --force

# Reset permission
chown -R www-data:www-data /var/www/pterodactyl/*

# Kembali online
php artisan up

echo "✅ Semua theme dan addon berhasil dihapus dan panel telah dipulihkan ke versi original."
