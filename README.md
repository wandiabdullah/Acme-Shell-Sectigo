Acme Shell Sectigo

🛠️ Initial Release – Version 0.1.4
🐚 Script: acme-caas-sectigo.sh

Shell-based automation script to request and manage SSL certificates using the ACME protocol with Sectigo CAAS. It supports multi-tenant configurations, custom working directories, and PHP handler detection for seamless integration with Nginx or Apache.

-------------------------------------------------------------------------------

✨ Features

- Supports Sectigo CAAS DV endpoint:
  https://acme.sectigo.com/v2/DV
- Fully automated certificate request using Certbot with EAB credentials
- Automatic web server detection and configuration for:
  - Nginx
  - Apache (mod_php or PHP-FPM)
- Auto-generated virtual host configuration:
  - Port 80 (HTTP + ACME challenge)
  - Port 443 (HTTPS with SSL paths)
- Auto-detects installed PHP version and configuration
- Supports multi-tenant setup via custom SECTIGO_DIR

-------------------------------------------------------------------------------

📁 File Structure

.
acme-caas-sectigo.sh   -> Main shell script  
config/                -> Optional: Configuration files  
logs/                  -> Optional: Log files  
README.md              -> Project documentation  

-------------------------------------------------------------------------------

📦 Requirements

- Ubuntu 20.04 / 22.04
- certbot (ACME client)
- curl, jq, grep, awk, sed
- Nginx or Apache installed
- Sectigo CAAS account & registered domain
- Root/sudo access

-------------------------------------------------------------------------------

⚙️ Installation

git clone https://github.com/wandiabdullah/Acme-Shell-Sectigo.git

cd Acme-Shell-Sectigo

chmod +x acme-caas-sectigo.sh

-------------------------------------------------------------------------------

🚀 Usage

sudo ./acme-caas-sectigo.sh

You’ll be prompted for:

- Domain name
- Working directory (optional; defaults to /opt/sectigo)
- PHP handler detection
- Web server (Nginx or Apache) virtual host setup

-------------------------------------------------------------------------------

🏷️ Environment Variable (Optional)

Variable      | Description                             | Default
--------------|-----------------------------------------|-----------------
SECTIGO_DIR   | Custom workdir for Certbot domain files | /opt/sectigo

-------------------------------------------------------------------------------

💡 Notes

- Script auto-detects installed PHP version (FPM or handler) and configures it in the virtual host.
- All icons, UI prompts, and extras have been removed for simplicity and automation purposes.

-------------------------------------------------------------------------------

🧾 Version History

v0.1.4 – Latest version
- Auto Apache support
- PHP handler detection
- Virtual host generator
- Multi-tenant support

v0.1.0 – Initial release
- Sectigo CAAS SSL integration via Certbot
- Custom tenant workdir
- PHP handler detection

-------------------------------------------------------------------------------

📌 Planned Features

- Auto-renewal cron setup
- Full logging and reporting
- Improved multi-tenant management
- GUI interface or web-based trigger

-------------------------------------------------------------------------------

🤝 Contributing

Pull requests and issue reports are welcome.
Please fork the repository and submit a PR with improvements.

-------------------------------------------------------------------------------

📄 License

This project is licensed under the MIT License.
