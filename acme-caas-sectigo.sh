#!/bin/bash

# === INTRODUCTION ===
echo "=============================================="
echo "          Sectigo CAAS ACME SSL Setup         "
echo "=============================================="
echo ""
echo "This script will issue an SSL certificate using:"
echo "Sectigo CAAS ACME endpoint with EAB credentials"
echo ""

# === INPUT ===
read -p "Enter your EAB KID                        : " EAB_KID
read -p "Enter your EAB HMAC key                   : " EAB_HMAC
read -p "Enter your domain name                    : " DOMAIN
read -p "Enter your email address                  : " EMAIL
read -p "Enter webroot path [default: /var/www/html]: " WEBROOT
read -p "Enter Sectigo working directory [default: /opt/sectigo]: " SECTIGO_DIR

# === DEFAULT VALUES ===
[ -z "$WEBROOT" ] && WEBROOT="/var/www/html"
[ -z "$SECTIGO_DIR" ] && SECTIGO_DIR="/opt/sectigo"

# === CREATE WORKING DIRS ===
DOMAIN_DIR="$SECTIGO_DIR/$DOMAIN"
CONFIG_DIR="$DOMAIN_DIR/config"
WORK_DIR="$DOMAIN_DIR/work"
LOGS_DIR="$DOMAIN_DIR/logs"

echo "Creating working directories in $DOMAIN_DIR ..."
mkdir -p "$CONFIG_DIR" "$WORK_DIR" "$LOGS_DIR"

# === CREATE DOMAIN MARKER IN /opt/sectigo ===
if [ "$SECTIGO_DIR" != "/opt/sectigo" ]; then
  echo "Adding domain record to /opt/sectigo/$DOMAIN ..."
  sudo mkdir -p "/opt/sectigo/$DOMAIN"
  echo "SECTIGO_DIR=$SECTIGO_DIR" > "/opt/sectigo/$DOMAIN/info.txt"
  echo "Created at: $(date)" >> "/opt/sectigo/$DOMAIN/info.txt"
fi

# === DETECT PHP ===
PHP_VERSION=$(php -v 2>/dev/null | grep -oP 'PHP \K[0-9]+\.[0-9]+' | head -n 1)
ENABLE_PHP=false

if [ -n "$PHP_VERSION" ]; then
  echo "Detected PHP version: $PHP_VERSION"
  if [ -e "/run/php/php${PHP_VERSION}-fpm.sock" ]; then
    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
    echo "PHP-FPM socket found at: $PHP_FPM_SOCK"
    ENABLE_PHP=true
  elif systemctl is-active --quiet php${PHP_VERSION}-fpm; then
    PHP_FPM_PORT="127.0.0.1:9000"
    echo "PHP-FPM is running over TCP: $PHP_FPM_PORT"
    ENABLE_PHP=true
  else
    echo "PHP-FPM not running. PHP support will be disabled."
  fi
else
  echo "PHP is not installed. PHP support will be disabled."
fi

# === REQUEST CERTIFICATE ===
echo "Requesting SSL certificate for $DOMAIN ..."
certbot certonly \
  --server https://acme.sectigo.com/v2/DV \
  --eab-kid "$EAB_KID" \
  --eab-hmac-key "$EAB_HMAC" \
  --email "$EMAIL" --agree-tos --non-interactive \
  --webroot -w "$WEBROOT" \
  -d "$DOMAIN" \
  --config-dir "$CONFIG_DIR" \
  --work-dir "$WORK_DIR" \
  --logs-dir "$LOGS_DIR"

if [ $? -ne 0 ]; then
  echo "Certificate issuance failed."
  exit 1
fi

# === GENERATE NGINX CONFIG ===
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
echo "Generating Nginx config for $DOMAIN ..."

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $WEBROOT;
    index index.php index.html index.htm;

    location /.well-known/acme-challenge/ {
        root $WEBROOT;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
EOF

if [ "$ENABLE_PHP" = true ]; then
  if [ -n "$PHP_FPM_SOCK" ]; then
    echo "        include snippets/fastcgi-php.conf;" >> "$NGINX_CONF"
    echo "        fastcgi_pass unix:$PHP_FPM_SOCK;" >> "$NGINX_CONF"
  else
    echo "        include snippets/fastcgi-php.conf;" >> "$NGINX_CONF"
    echo "        fastcgi_pass $PHP_FPM_PORT;" >> "$NGINX_CONF"
  fi
else
  echo "        return 500;" >> "$NGINX_CONF"
  echo "        # PHP not available" >> "$NGINX_CONF"
fi

cat >> "$NGINX_CONF" <<EOF
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     $CONFIG_DIR/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key $CONFIG_DIR/live/$DOMAIN/privkey.pem;

    root $WEBROOT;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
EOF

if [ "$ENABLE_PHP" = true ]; then
  if [ -n "$PHP_FPM_SOCK" ]; then
    echo "        include snippets/fastcgi-php.conf;" >> "$NGINX_CONF"
    echo "        fastcgi_pass unix:$PHP_FPM_SOCK;" >> "$NGINX_CONF"
  else
    echo "        include snippets/fastcgi-php.conf;" >> "$NGINX_CONF"
    echo "        fastcgi_pass $PHP_FPM_PORT;" >> "$NGINX_CONF"
  fi
else
  echo "        return 500;" >> "$NGINX_CONF"
  echo "        # PHP not available" >> "$NGINX_CONF"
fi

cat >> "$NGINX_CONF" <<EOF
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN.conf"

# === RELOAD NGINX ===
echo "Reloading Nginx ..."
nginx -t && systemctl reload nginx

# === TEST HTTPS ===
echo "Testing HTTPS for $DOMAIN ..."
sleep 5
if curl -Is "https://$DOMAIN" | grep -qE "200|301|302"; then
  echo "$DOMAIN is now active with HTTPS."
else
  echo "HTTPS may not be working. Check DNS, Nginx, or certificate paths."
fi
