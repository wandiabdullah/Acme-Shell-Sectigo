Acme Shell Sectigo

🛠️ Latest Release – Version 0.3.0
🐚 Script: acme-caas-sectigo.sh

Shell-based automation script to request and manage SSL certificates using the ACME protocol with Sectigo CAAS. It supports both DV and OV certificate types, multi-tenant configurations, custom working directories, wildcard domain validation via DNS, and PHP handler detection for seamless integration with Nginx or Apache.

-------------------------------------------------------------------------------

✨ Features

- **Multiple certificate validation types:**
  - **DV (Domain Validation)**: https://acme.sectigo.com/v2/DV
  - **OV (Organization Validation)**: https://acme.sectigo.com/v2/OV
- Fully automated certificate request using Certbot with EAB credentials
- **Wildcard domain support (*.domain.com)** with DNS validation:
  - **Manual DNS validation**: Interactive mode with step-by-step instructions
  - **Cloudflare DNS validation**: Automated DNS challenge using API token
- Automatic web server detection and configuration for:
  - Nginx
  - Apache (mod_php or PHP-FPM)
- Auto-generated virtual host configuration:
  - Port 80 (HTTP + ACME challenge)
  - Port 443 (HTTPS with SSL paths)
- Auto-detects installed PHP version and configuration
- Supports multi-tenant setup via custom SECTIGO_DIR
- Secure input handling for sensitive credentials (hidden API token input)

-------------------------------------------------------------------------------

📁 File Structure

.
acme-caas-sectigo.sh   -> Main shell script  
config/                -> Optional: Configuration files  
logs/                  -> Optional: Log files  
README.md              -> Project documentation  

-------------------------------------------------------------------------------

📦 Requirements

- Ubuntu 20.04 / 22.04 (or compatible Linux distribution)
- certbot (ACME client)
- curl, jq, grep, awk, sed
- Nginx or Apache installed
- Sectigo CAAS account & registered domain
- Root/sudo access
- **For wildcard domains with Cloudflare:**
  - `python3-certbot-dns-cloudflare` plugin (install via `sudo apt install python3-certbot-dns-cloudflare` or `pip install certbot-dns-cloudflare`)
  - Cloudflare API token with DNS edit permissions

-------------------------------------------------------------------------------

⚙️ Installation

git clone https://github.com/wandiabdullah/Acme-Shell-Sectigo.git

cd Acme-Shell-Sectigo

chmod +x acme-caas-sectigo.sh

-------------------------------------------------------------------------------

🚀 Usage

sudo ./acme-caas-sectigo.sh

You'll be prompted for:

**1. Certificate Type Selection:**
- Choose between DV (Domain Validation) or OV (Organization Validation)
- Enter 1 for DV or 2 for OV

**2. Certificate Details:**
- EAB KID and EAB HMAC key (from Sectigo CAAS - ensure credentials match your selected certificate type)
- Domain name (supports regular domains and wildcards like *.example.com)
- Email address
- Certificate name (optional, defaults to domain name)
- Webroot path (optional, defaults to /var/www/DOMAIN)
- Working directory (optional, defaults to /opt/sectigo)

**For wildcard domains (*.example.com):**
- Choose DNS validation method: `manual` or `cloudflare`
- If `manual`: Follow the interactive prompts to add TXT records to your DNS
- If `cloudflare`: Enter your Cloudflare API token (input is hidden for security)

The script will:
1. Detect your web server (Nginx or Apache)
2. Auto-detect PHP version and configuration
3. Request SSL certificate from Sectigo via ACME (DV or OV endpoint)
4. Configure virtual hosts for HTTP (port 80) and HTTPS (port 443)
5. Reload your web server with the new configuration

-------------------------------------------------------------------------------

🏷️ Environment Variable (Optional)

Variable      | Description                             | Default
--------------|-----------------------------------------|-----------------
SECTIGO_DIR   | Custom workdir for Certbot domain files | /opt/sectigo

-------------------------------------------------------------------------------

💡 Notes

- Script auto-detects installed PHP version (FPM or handler) and configures it in the virtual host.
- **Certificate type selection**: Choose between DV (Domain Validation) or OV (Organization Validation) at the start.
- **Important**: Ensure your EAB credentials (KID and HMAC key) match the certificate type you selected - DV and OV use different credentials in Sectigo CAAS.
- **Wildcard domains** (e.g., `*.indogemsauction.com`) automatically trigger DNS validation.
- For **manual DNS validation**, you'll need to add TXT records to your DNS provider as instructed by Certbot.
- For **Cloudflare DNS validation**, ensure your API token has `Zone:DNS:Edit` permissions.
- All icons, UI prompts, and extras have been removed for simplicity and automation purposes.
- The script validates DNS method input and checks for required Certbot plugins before proceeding.

-------------------------------------------------------------------------------

🧾 Version History

v0.3.0 – Latest version (November 2025)
- **DV and OV certificate type selection** at script start
- Dynamic ACME endpoint based on certificate type
- Separate EAB credential support for DV/OV
- Enhanced user guidance for certificate type selection

v0.2.0 – (November 2025)
- **Wildcard domain support** with DNS validation
- **Manual DNS validation** mode (interactive)
- **Cloudflare DNS validation** with automated API integration
- Input validation for DNS method selection
- Plugin availability checking for Cloudflare
- Secure hidden input for API tokens
- Enhanced error handling and user guidance

v0.1.4
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
- Additional DNS provider support (Route53, DigitalOcean, etc.)
- EV (Extended Validation) certificate support
- GUI interface or web-based trigger

-------------------------------------------------------------------------------

🤝 Contributing

Pull requests and issue reports are welcome.
Please fork the repository and submit a PR with improvements.

-------------------------------------------------------------------------------

📄 License

This project is licensed under the MIT License.
