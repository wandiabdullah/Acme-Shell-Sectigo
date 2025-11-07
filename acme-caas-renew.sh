#!/bin/bash

# === INTRODUCTION ===
echo "=============================================="
echo "    Sectigo CAAS SSL Renewal & Installer     "
echo "=============================================="
echo ""
echo "This script will:"
echo "1. Renew SSL certificates automatically"
echo "2. Install renewed certificates to web server"
echo ""

# === PARSE ARGUMENTS ===
NON_INTERACTIVE=false
SECTIGO_DIR_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --sectigo-dir)
      SECTIGO_DIR_ARG="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# === INPUT ===
if [ "$NON_INTERACTIVE" = true ]; then
  SECTIGO_DIR="${SECTIGO_DIR_ARG:-/opt/sectigo}"
else
  read -p "Enter Sectigo working directory [default: /opt/sectigo]: " SECTIGO_DIR
  [ -z "$SECTIGO_DIR" ] && SECTIGO_DIR="/opt/sectigo"
fi

# === SETUP LOGGING ===
LOG_FILE="/var/log/sectigo-renewal.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting renewal process"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# === CHECK IF DIRECTORY EXISTS ===
if [ ! -d "$SECTIGO_DIR" ]; then
  echo "Error: Directory $SECTIGO_DIR does not exist."
  echo "Please run acme-caas-sectigo.sh first to create certificates."
  exit 1
fi

# === DETECT WEB SERVER ===
if systemctl is-active --quiet apache2; then
  WEB_SERVER="apache"
  WEB_SERVICE="apache2"
elif systemctl is-active --quiet nginx; then
  WEB_SERVER="nginx"
  WEB_SERVICE="nginx"
else
  echo "Warning: No supported web server detected (Apache or Nginx)."
  echo "Certificates will be renewed but not installed to web server."
  WEB_SERVER="none"
fi

# === FIND ALL DOMAIN DIRECTORIES ===
echo ""
echo "Scanning for SSL certificates in $SECTIGO_DIR..."
DOMAIN_DIRS=$(find "$SECTIGO_DIR" -maxdepth 1 -type d ! -path "$SECTIGO_DIR" 2>/dev/null)

if [ -z "$DOMAIN_DIRS" ]; then
  echo "No domain directories found in $SECTIGO_DIR"
  exit 1
fi

echo "Found the following domains:"
for DIR in $DOMAIN_DIRS; do
  DOMAIN=$(basename "$DIR")
  echo "  - $DOMAIN"
done
echo ""

# === RENEWAL PROCESS ===
echo "Starting certificate renewal process..."
echo ""

RENEWAL_COUNT=0
SUCCESS_COUNT=0
FAILED_DOMAINS=""

for DIR in $DOMAIN_DIRS; do
  DOMAIN=$(basename "$DIR")
  CONFIG_DIR="$DIR/config"
  WORK_DIR="$DIR/work"
  LOGS_DIR="$DIR/logs"
  
  # Check if config directory exists
  if [ ! -d "$CONFIG_DIR" ]; then
    echo "⚠️  Skipping $DOMAIN: config directory not found"
    continue
  fi
  
  # Find certificate name from renewal configs
  RENEWAL_DIR="$CONFIG_DIR/renewal"
  if [ ! -d "$RENEWAL_DIR" ]; then
    echo "⚠️  Skipping $DOMAIN: renewal directory not found"
    continue
  fi
  
  # Process each certificate in this domain
  for CERT_CONF in "$RENEWAL_DIR"/*.conf; do
    if [ ! -f "$CERT_CONF" ]; then
      continue
    fi
    
    CERT_NAME=$(basename "$CERT_CONF" .conf)
    RENEWAL_COUNT=$((RENEWAL_COUNT + 1))
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📜 Certificate: $CERT_NAME"
    echo "🌐 Domain: $DOMAIN"
    echo "📅 Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check certificate expiry
    CERT_FILE="$CONFIG_DIR/live/$CERT_NAME/cert.pem"
    if [ -f "$CERT_FILE" ]; then
      EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
      EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
      NOW_EPOCH=$(date +%s)
      DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
      echo "📊 Days until expiry: $DAYS_LEFT days"
      echo "📆 Expires on: $EXPIRY"
    fi
    
    # Attempt renewal
    echo "🔄 Attempting renewal..."
    certbot renew \
      --cert-name "$CERT_NAME" \
      --config-dir "$CONFIG_DIR" \
      --work-dir "$WORK_DIR" \
      --logs-dir "$LOGS_DIR" \
      --deploy-hook "echo '[$(date '+%Y-%m-%d %H:%M:%S')] Certificate renewed: $CERT_NAME'"
    
    RENEWAL_RESULT=$?
    
    if [ $RENEWAL_RESULT -eq 0 ]; then
      echo "✅ Successfully renewed: $CERT_NAME at $(date '+%Y-%m-%d %H:%M:%S')"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      
      # Verify new certificate
      CERT_FILE="$CONFIG_DIR/live/$CERT_NAME/cert.pem"
      if [ -f "$CERT_FILE" ]; then
        NEW_EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
        echo "✨ New expiry date: $NEW_EXPIRY"
      fi
      
      # Install to web server if applicable
      if [ "$WEB_SERVER" != "none" ]; then
        CERT_DIR="$CONFIG_DIR/live/$CERT_NAME"
        
        if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
          echo "📦 Installing certificate to $WEB_SERVER..."
          
          # Update web server configuration if needed
          if [ "$WEB_SERVER" = "nginx" ]; then
            NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
            if [ -f "$NGINX_CONF" ]; then
              # Check if certificate paths are already configured
              if grep -q "ssl_certificate.*$CERT_DIR" "$NGINX_CONF"; then
                echo "   ✅ Certificate paths already configured in Nginx"
              else
                echo "   ⚠️  Certificate installed, manual configuration may be needed"
              fi
            fi
          elif [ "$WEB_SERVER" = "apache" ]; then
            APACHE_CONF="/etc/apache2/sites-available/$DOMAIN.conf"
            if [ -f "$APACHE_CONF" ]; then
              # Check if certificate paths are already configured
              if grep -q "SSLCertificateFile.*$CERT_DIR" "$APACHE_CONF"; then
                echo "   ✅ Certificate paths already configured in Apache"
              else
                echo "   ⚠️  Certificate installed, manual configuration may be needed"
              fi
            fi
          fi
        fi
      fi
    else
      echo "❌ Failed to renew: $CERT_NAME at $(date '+%Y-%m-%d %H:%M:%S')"
      echo "❌ Exit code: $RENEWAL_RESULT"
      FAILED_DOMAINS="$FAILED_DOMAINS\n  - $CERT_NAME ($DOMAIN) - Failed at $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    echo ""
  done
done

# === RELOAD WEB SERVER ===
if [ "$WEB_SERVER" != "none" ] && [ $SUCCESS_COUNT -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔄 Reloading $WEB_SERVER to apply changes at $(date '+%Y-%m-%d %H:%M:%S')..."
  
  if [ "$WEB_SERVER" = "nginx" ]; then
    nginx -t && systemctl reload nginx
  elif [ "$WEB_SERVER" = "apache" ]; then
    apache2ctl configtest && systemctl reload apache2
  fi
  
  RELOAD_RESULT=$?
  if [ $RELOAD_RESULT -eq 0 ]; then
    echo "✅ $WEB_SERVER reloaded successfully at $(date '+%Y-%m-%d %H:%M:%S')"
  else
    echo "❌ Failed to reload $WEB_SERVER - please check configuration (Exit code: $RELOAD_RESULT)"
  fi
fi

# === SUMMARY ===
echo ""
echo "=============================================="
echo "           Renewal Summary                    "
echo "=============================================="
echo "⏰ Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "📊 Total certificates processed: $RENEWAL_COUNT"
echo "✅ Successfully renewed: $SUCCESS_COUNT"
echo "❌ Failed: $((RENEWAL_COUNT - SUCCESS_COUNT))"

if [ -n "$FAILED_DOMAINS" ]; then
  echo ""
  echo "❌ Failed domains:"
  echo -e "$FAILED_DOMAINS"
fi

echo ""
echo "✅ Renewal process completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo "📝 Log file: $LOG_FILE"
echo "=============================================="
echo ""

# === EXIT ===
exit 0
