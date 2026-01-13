
        GITHUB_TOKEN="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"
        REPO_URL="https://github.com/KiwamiXq1031/installer-premium.git"
        TEMP_DIR="installer-premium"

        git clone "https://${GITHUB_TOKEN}@github.com/KiwamiXq1031/installer-premium.git" "$TEMP_DIR"

        sudo mv "$TEMP_DIR/ElysiumTheme.zip" /var/www/
        unzip -o /var/www/ElysiumTheme.zip -d /var/www/
        rm -rf "$TEMP_DIR"
        rm -f /var/www/ElysiumTheme.zip

        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg || true
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null

        sudo apt update -y
        sudo apt install -y nodejs npm
        sudo npm install -g yarn

        cd /var/www/pterodactyl || exit
        yarn
        yarn build:production
        php artisan migrate --force
        php artisan view:clear
        animate_text() {
    local text=$1
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
    done
    echo ""
}
        animate_text "Tema Elysium berhasil diinstal."
