# Acme Shell Sectigo

> 🛠️ Initial Release – Version 0.1  
> 🐚 Script: `acme-caas-sectigo.sh`

Shell-based automation script to request and manage SSL certificates using the **ACME protocol** with **Sectigo CAAS**. It supports multi-tenant configuration, custom working directories, and PHP handler detection for seamless integration into existing web server environments.

---

## 🚀 Features

- ✅ Request SSL certificates from Sectigo CAAS using Certbot
- 📁 Custom working directory for each tenant (`SECTIGO_DIR`)
- 🔍 Auto-detect PHP-FPM or other PHP handlers in VirtualHost
- 🔧 Automatically update Nginx/Apache configurations
- 🧼 Minimal, no-icon, clean shell environment

---

## 📁 File Structure

```bash
.
├── acme-caas-sectigo.sh     # Main shell script
├── config/                  # (optional) Configuration files
├── logs/                    # Log files (optional)
├── README.md                # Documentation


📦 Requirements
Ubuntu 20.04 / 22.04

certbot (ACME client)

curl, jq, grep, awk, sed

Nginx or Apache installed

Sectigo CAAS account & domain registered

Root/sudo access

⚙️ Installation

git clone https://github.com/wandiabdullah/Acme-Shell-Sectigo.git
cd Acme-Shell-Sectigo
chmod +x acme-caas-sectigo.sh


🚀 Usage

sudo ./acme-caas-sectigo.sh

You’ll be prompted for:

Domain name

Working directory (optional; defaults to /opt/sectigo)

PHP handler detection

Nginx virtual host setup or update


🏷️ Environment Variable (Optional)
Variable	Description	Default
SECTIGO_DIR	Custom workdir for tenant's Certbot files	/opt/sectigo

💡 Notes
Script auto-detects PHP version installed (FPM or handler) and includes it in your web server config.

All icons, UI prompts, and extras have been removed for simplicity and automation purposes.

🧾 Version
v0.1.0 – Initial version

Sectigo CAAS SSL integration via Certbot

Custom tenant workdir support

Auto PHP handler detection for vhost

📌 Planned Features
 Auto-renewal cron setup

 Full logging and reporting

 Improved multi-tenant handling

 GUI interface or web-based trigger

🤝 Contributing
Pull requests and issue reports are welcome.
Please fork the repository and submit a PR for any improvements.

📄 License
MIT License