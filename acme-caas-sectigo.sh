#!/bin/bash

# === INTRODUCTION ===
echo "=============================================="
echo "         Sectigo CAAS ACME SSL Setup          "
echo "=============================================="
echo ""
echo "This script will issue an SSL certificate using:"
echo "Sectigo CAAS ACME endpoint with EAB credentials"
echo ""

# === SELECT CERTIFICATE TYPE ===
echo "Select certificate validation type:"
echo "1) DV (Domain Validation)"
echo "2) OV (Organization Validation)"
read -p "Enter your choice (1 or 2): " CERT_TYPE_CHOICE

while [[ "$CERT_TYPE_CHOICE" != "1" && "$CERT_TYPE_CHOICE" != "2" ]]; do
  echo "Invalid choice. Please enter 1 for DV or 2 for OV."
  read -p "Enter your choice (1 or 2): " CERT_TYPE_CHOICE
done

if [ "$CERT_TYPE_CHOICE" = "1" ]; then
  CERT_TYPE="DV"
  ACME_SERVER="https://acme.sectigo.com/v2/DV"
  echo "Selected: Domain Validation (DV)"
else
  CERT_TYPE="OV"
  ACME_SERVER="https://acme.sectigo.com/v2/OV"
  echo "Selected: Organization Validation (OV)"
fi
echo ""

# === INPUT ===
read -p "Enter your EAB KID                        : " EAB_KID
read -p "Enter your EAB HMAC key                   : " EAB_HMAC
read -p "Enter your domain name                    : " DOMAIN
read -p "Enter your email address                  : " EMAIL
read -p "Enter certificate name (cert-name) [default: $DOMAIN]: " CERT_NAME
read -p "Enter webroot path [default: /var/www/$DOMAIN]: " WEBROOT
read -p "Enter Sectigo working directory [default: /opt/sectigo]: " SECTIGO_DIR

# === CHECK FOR WILDCARD DOMAIN ===
IS_WILDCARD=false
if [[ "$DOMAIN" == \** ]]; then
  IS_WILDCARD=true
  echo "Wildcard domain detected. DNS validation will be used."
  read -p "Choose DNS validation method (manual/cloudflare): " DNS_METHOD
  while [[ "$DNS_METHOD" != "manual" && "$DNS_METHOD" != "cloudflare" ]]; do
    echo "Invalid choice. Please enter 'manual' or 'cloudflare'."
    read -p "Choose DNS validation method (manual/cloudflare): " DNS_METHOD
  done
  if [ "$DNS_METHOD" = "cloudflare" ]; then
    # Check if certbot-dns-cloudflare plugin is available
    if ! certbot plugins 2>/dev/null | grep -q "dns-cloudflare"; then
      echo "Error: certbot-dns-cloudflare plugin is not installed."
      echo "Please install it using: sudo apt install python3-certbot-dns-cloudflare (on Ubuntu/Debian)"
      echo "Or: pip install certbot-dns-cloudflare"
      exit 1
    fi
    read -s -p "Enter your Cloudflare API token: " CF_API_TOKEN
    echo ""  # Newline after hidden input
    # Create Cloudflare credentials file
    CF_CRED_FILE="$CONFIG_DIR/cloudflare.ini"
    echo "dns_cloudflare_api_token = $CF_API_TOKEN" > "$CF_CRED_FILE"
    chmod 600 "$CF_CRED_FILE"
  fi
fi

# === DEFAULT VALUES ===
[ -z "$WEBROOT" ] && WEBROOT="/var/www/$DOMAIN"
[ -z "$SECTIGO_DIR" ] && SECTIGO_DIR="/opt/sectigo"
[ -z "$CERT_NAME" ] && CERT_NAME="$DOMAIN"

# === CREATE DIRECTORIES ===
DOMAIN_DIR="$SECTIGO_DIR/$DOMAIN"
CONFIG_DIR="$DOMAIN_DIR/config"
WORK_DIR="$DOMAIN_DIR/work"
LOGS_DIR="$DOMAIN_DIR/logs"
CERT_DIR="$CONFIG_DIR/live/$CERT_NAME"

echo "Creating working directories in $DOMAIN_DIR ..."
mkdir -p "$CONFIG_DIR" "$WORK_DIR" "$LOGS_DIR" "$WEBROOT"

# === OPTIONAL INFO METADATA ===
if [ "$SECTIGO_DIR" != "/opt/sectigo" ]; then
  mkdir -p "/opt/sectigo/$DOMAIN"
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

# === DETECT WEB SERVER ===
if systemctl is-active --quiet apache2; then
  WEB_SERVER="apache"
elif systemctl is-active --quiet nginx; then
  WEB_SERVER="nginx"
else
  echo "No supported web server detected (Apache or Nginx)."
  exit 1
fi

# === CREATE VHOST PORT 80 BEFORE CERTBOT ===
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
}
EOF

  ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN.conf"
  nginx -t && systemctl reload nginx

elif [ "$WEB_SERVER" = "apache" ]; then
  APACHE_CONF="/etc/apache2/sites-available/$DOMAIN.conf"
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
EOF

  a2ensite "$DOMAIN.conf"
  apache2ctl configtest && systemctl reload apache2
fi

# === REQUEST CERTIFICATE ===
echo "Requesting SSL certificate for $DOMAIN ..."

if [ "$IS_WILDCARD" = true ]; then
  if [ "$DNS_METHOD" = "manual" ]; then
    certbot certonly \
      -v \
      --server "$ACME_SERVER" \
      --eab-kid "$EAB_KID" \
      --eab-hmac-key "$EAB_HMAC" \
      --email "$EMAIL" \
      --agree-tos \
      --manual \
      --preferred-challenges dns \
      -d "$DOMAIN" \
      --debug-challenges \
      --cert-name "$CERT_NAME" \
      --config-dir "$CONFIG_DIR" \
      --work-dir "$WORK_DIR" \
      --logs-dir "$LOGS_DIR"
  elif [ "$DNS_METHOD" = "cloudflare" ]; then
    certbot certonly \
      -v \
      --server "$ACME_SERVER" \
      --eab-kid "$EAB_KID" \
      --eab-hmac-key "$EAB_HMAC" \
      --email "$EMAIL" \
      --agree-tos \
      --non-interactive \
      --dns-cloudflare \
      --dns-cloudflare-credentials "$CF_CRED_FILE" \
      -d "$DOMAIN" \
      --debug-challenges \
      --cert-name "$CERT_NAME" \
      --config-dir "$CONFIG_DIR" \
      --work-dir "$WORK_DIR" \
      --logs-dir "$LOGS_DIR"
  fi
else
  certbot certonly \
    -v \
    --server "$ACME_SERVER" \
    --eab-kid "$EAB_KID" \
    --eab-hmac-key "$EAB_HMAC" \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive \
    --webroot -w "$WEBROOT" \
    -d "$DOMAIN" \
    --debug-challenges \
    --cert-name "$CERT_NAME" \
    --config-dir "$CONFIG_DIR" \
    --work-dir "$WORK_DIR" \
    --logs-dir "$LOGS_DIR"
fi

if [ $? -ne 0 ]; then
  echo "Certificate issuance failed."
  exit 1
fi

# === APPEND VHOST PORT 443 ===
if [ "$WEB_SERVER" = "nginx" ]; then
  cat >> "$NGINX_CONF" <<EOF

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

  nginx -t && systemctl reload nginx

elif [ "$WEB_SERVER" = "apache" ]; then
  cat >> "$APACHE_CONF" <<EOF

<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot $WEBROOT

    SSLEngine on
    SSLCertificateFile    $CERT_DIR/fullchain.pem
    SSLCertificateKeyFile $CERT_DIR/privkey.pem

    <Directory $WEBROOT>
        AllowOverride All
        Require all granted
    </Directory>
EOF

  if [ "$ENABLE_PHP" = true ] && [ -n "$PHP_FPM_SOCK" ]; then
    cat >> "$APACHE_CONF" <<EOF
    <FilesMatch \.php$>
        SetHandler "proxy:unix:$PHP_FPM_SOCK|fcgi://localhost/"
    </FilesMatch>
EOF
  fi

  cat >> "$APACHE_CONF" <<EOF
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-access.log combined
</VirtualHost>
EOF

  apache2ctl configtest && systemctl reload apache2
fi

# === DONE ===
echo "SSL certificate installed and web server configured for $DOMAIN"
