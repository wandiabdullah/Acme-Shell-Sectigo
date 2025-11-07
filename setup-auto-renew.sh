#!/bin/bash

# === INTRODUCTION ===
echo "=============================================="
echo "    Sectigo CAAS SSL Auto-Renewal Setup      "
echo "=============================================="
echo ""
echo "This script will set up automatic SSL certificate renewal"
echo "using cron job for Sectigo CAAS certificates."
echo ""

# === CHECK ROOT ===
if [ "$EUID" -ne 0 ]; then 
  echo "Error: This script must be run as root (use sudo)"
  exit 1
fi

# === INPUT ===
read -p "Enter Sectigo working directory [default: /opt/sectigo]: " SECTIGO_DIR
[ -z "$SECTIGO_DIR" ] && SECTIGO_DIR="/opt/sectigo"

# === CHECK IF RENEWAL SCRIPT EXISTS ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENEWAL_SCRIPT="$SCRIPT_DIR/acme-caas-renew.sh"

if [ ! -f "$RENEWAL_SCRIPT" ]; then
  echo "Error: Renewal script not found at $RENEWAL_SCRIPT"
  echo "Please ensure acme-caas-renew.sh is in the same directory."
  exit 1
fi

# Make renewal script executable
chmod +x "$RENEWAL_SCRIPT"

# === CRON SCHEDULE OPTIONS ===
echo ""
echo "Select renewal schedule:"
echo "1) Daily at 2:00 AM"
echo "2) Weekly (Sunday at 2:00 AM)"
echo "3) Monthly (1st day at 2:00 AM)"
echo "4) Twice daily (2:00 AM and 2:00 PM)"
echo "5) Custom schedule"
read -p "Enter your choice (1-5): " SCHEDULE_CHOICE

while [[ ! "$SCHEDULE_CHOICE" =~ ^[1-5]$ ]]; do
  echo "Invalid choice. Please enter 1-5."
  read -p "Enter your choice (1-5): " SCHEDULE_CHOICE
done

case $SCHEDULE_CHOICE in
  1)
    CRON_SCHEDULE="0 2 * * *"
    SCHEDULE_DESC="Daily at 2:00 AM"
    ;;
  2)
    CRON_SCHEDULE="0 2 * * 0"
    SCHEDULE_DESC="Weekly on Sunday at 2:00 AM"
    ;;
  3)
    CRON_SCHEDULE="0 2 1 * *"
    SCHEDULE_DESC="Monthly on the 1st at 2:00 AM"
    ;;
  4)
    CRON_SCHEDULE="0 2,14 * * *"
    SCHEDULE_DESC="Twice daily at 2:00 AM and 2:00 PM"
    ;;
  5)
    echo ""
    echo "Enter custom cron schedule (format: minute hour day month weekday)"
    echo "Example: 0 3 * * * (runs daily at 3:00 AM)"
    read -p "Cron schedule: " CRON_SCHEDULE
    SCHEDULE_DESC="Custom: $CRON_SCHEDULE"
    ;;
esac

# === CREATE CRON JOB ===
CRON_COMMAND="$RENEWAL_SCRIPT --non-interactive --sectigo-dir $SECTIGO_DIR >> /var/log/sectigo-renewal.log 2>&1"
CRON_JOB="$CRON_SCHEDULE $CRON_COMMAND"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$RENEWAL_SCRIPT"; then
  echo ""
  echo "⚠️  A cron job for this renewal script already exists."
  read -p "Do you want to replace it? (y/n): " REPLACE
  
  if [[ "$REPLACE" =~ ^[Yy]$ ]]; then
    # Remove old cron job
    crontab -l 2>/dev/null | grep -v "$RENEWAL_SCRIPT" | crontab -
    echo "Old cron job removed."
  else
    echo "Installation cancelled."
    exit 0
  fi
fi

# Add new cron job
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Cron job successfully installed!"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Schedule: $SCHEDULE_DESC"
  echo "Script: $RENEWAL_SCRIPT"
  echo "Log file: /var/log/sectigo-renewal.log"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "To view current cron jobs: crontab -l"
  echo "To edit cron jobs: crontab -e"
  echo "To view renewal logs: tail -f /var/log/sectigo-renewal.log"
  echo ""
else
  echo "❌ Failed to install cron job."
  exit 1
fi

# === CREATE LOG FILE ===
touch /var/log/sectigo-renewal.log
chmod 644 /var/log/sectigo-renewal.log

# === OPTIONAL: TEST RUN ===
echo ""
read -p "Do you want to perform a test run now? (y/n): " TEST_RUN

if [[ "$TEST_RUN" =~ ^[Yy]$ ]]; then
  echo ""
  echo "Running renewal script..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bash "$RENEWAL_SCRIPT"
fi

echo ""
echo "✅ Auto-renewal setup completed successfully!"
echo "=============================================="

exit 0
