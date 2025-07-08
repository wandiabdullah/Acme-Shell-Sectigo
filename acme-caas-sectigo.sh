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
read -p "Enter webroot path [default: /var/www/$DOMAIN]: " WEBROOT
read -p "Enter Sectigo working directory [default: /opt/sectigo]: " SECTIGO_DIR

# === DEFAULT VALUES ===
[ -z "$WEBROOT" ] && WEBROOT="/var/www/$DOMAIN"
[ -z "$SECTIGO_DIR" ] && SECTIGO_DIR="/opt/sectigo"

# === CREATE WORKING DIRS ===
DOMAIN_DIR="$SECTIGO_DIR/$DOMAIN"
CONFIG_DIR="$DOMAIN_DIR/config"
WORK_DIR="$DOMAIN_DIR/work"
LOGS_DIR="$DOMAIN_DIR/logs"
CERT_DIR="$CONFIG_DIR/live/$DOMAIN"

echo "Creating working directories in $DOMAIN_DIR ..."
mkdir -p "$CONFIG_DIR" "$WORK_DIR" "$LOGS_DIR" "$WEBROOT"

# === MARK TENANT INFO ===
if [ "$SECTIGO_DIR" != "/opt/sectigo" ]; then
  sudo mkdir -p "/opt/sectigo/$DOMAIN"
  echo "SECTIGO_DIR=$SECTIGO_DIR" > "/opt/sectigo/$DOMAIN/info.txt"
  echo "Created at: $(date)" >> "/opt/sectigo/$DOMAIN/info.txt"
fi

# === DETECT PHP ===
PHP_VERSION=$(php -v 2>/dev/null | grep -oP 'PHP \K[0-9]+\.[0-9]+' | head -n 1)
ENABLE_PHP=false

if [ -n "$PHP_VERSION" ]; then
  if [ -e "/run/php/php${PHP_VERSION}-fpm.sock" ]; then
    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
    ENABLE_PHP=true
  elif systemctl is-active --quiet php${PHP_VERSION}-fpm; then
    PHP_FPM_PORT="127.0.0.1:9000"
    ENABLE_PHP=true
  fi
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

# === DETECT WEB SERVER ===
if systemctl is-active --quiet apache2; then
  WEB_SERVER="apache"
elif systemctl is-active --quiet nginx; then
  WEB_SERVER="nginx"
else
  echo "No supported web server detected (Apache or Nginx)."
  exit 1
fi

# === CONFIGURE NGINX ===
if [ "$WEB_SERVER" = "nginx" ]; then
  NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"

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

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;

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
  nginx -t && systemctl reload nginx

# === CONFIGURE APACHE ===
elif [ "$WEB_SERVER" = "apache" ]; then
  APACHE_CONF="/etc/apache2/sites-available/$DOMAIN.conf"

  if apache2ctl -M | grep -q php; then
    cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $WEBROOT

    <Directory $WEBROOT>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot $WEBROOT

    SSLEngine on
    SSLCertificateFile      $CERT_DIR/fullchain.pem
    SSLCertificateKeyFile   $CERT_DIR/privkey.pem

    <Directory $WEBROOT>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-access.log combined
</VirtualHost>
EOF

  else
    cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $WEBROOT

    <Directory $WEBROOT>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot $WEBROOT

    SSLEngine on
    SSLCertificateFile      $CERT_DIR/fullchain.pem
    SSLCertificateKeyFile   $CERT_DIR/privkey.pem

    <Directory $WEBROOT>
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:$PHP_FPM_SOCK|fcgi://localhost/"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-access.log combined
</VirtualHost>
EOF
  fi

  a2ensite "$DOMAIN.conf"
  apache2ctl configtest && systemctl reload apache2
fi

# === DONE ===
echo "SSL certificate installed and virtual host configured for $DOMAIN"
