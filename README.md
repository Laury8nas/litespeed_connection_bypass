# LiteSpeed Web server connection timeout limit bypass script for Hostinger
This bash script automates the setup, management, and teardown of a PHP development environment with a custom bypass scheme. It includes functionality to modify website's configuration files (wp-config.php and .htaccess), manage a PHP development server, and monitor its health. Additionally, the script ensures cleanup and restoration of the original environment state when the 59 minute timer runs out. This script is created only for WordPress websites, but can be modified to suit individual needs.


### How the script bypass the limit?

The main principle of how it bypass the connection timeout limit goes to the:
- PHP development server creation in user namespace to avoid problems with baked-in lsphp limits;
- Reverse-proxying the requests back and forth from the visitor through the LiteSpeed Web server via .htaccess file rules to the created PHP development server.

![Image](https://github.com/user-attachments/assets/0d559321-6849-447d-9603-8cba582da00a)

### Existing files modification and new files creation

Since this script is adopted only for WordPress websites, it modifies (or better say "replaces") these files:
- .htaccess - it adds proxying, URL rewriting rules and timeout limit ignorance rules to the file;
- wp-config.php - the script adds the SSL configuration snippet to avoid HTTPS errors when using this script.

Although the script modifies existing files, it also creates backups of the original files, so the user can easily revert the changes in case something goes wrong. The backup files should look like this (the files will have unique number attached at the end of the file name):
- `wp-config.php.backup_1737537444`
- `.htaccess.backup_1737537444`

Besides modifying the existing files, the script creates some new temporary files to ensure the automatic reversability function after the timer runs out. These files mainly holds the PIDs of the created processes and will be named like these:
- `.background_pid`
- `.monitor_php_pid`
- `.php_server_pid`
- `.script_pid`
- `.timer_pid`

To make sure, that every event is logged properly for debugging purposes, the script creates two log files:
- `php_bypass.log` - this log file will contain all events related to the script behavior;
- `php_server.log` - this log file will contain all events related to the PHP development server.

### Menu functions

This bash script will offer two options after execution:

**1. Create bypassing scheme**

This option is created for creating the bypassing scheme (launching the whole mechanism). However, for the scheme to work, the user needs to select what PHP version the user wants to use for the PHP development server:

![Image](https://github.com/user-attachments/assets/603b2a96-5a1a-44c1-9faf-fafd9768ffcb)

**2. Revert changes**

This option is created for reverting all the changes to the original state. This option should clear all the temporary files, restore the original files and stop all the script-related processes. Keep in mind, that two log files (php_bypass.log and php_server.log) will not be removed after selecting this option. This is done to ensure a proper debugging process.

![Image](https://github.com/user-attachments/assets/92b586ec-74ae-4ff0-b3b6-b2b9a6e92a5b)

### Features

The main additional features of this bash script are:
- Automatic reversion function which activates after 59 minutes from the script launch;
- PHP development server automatic restart (up to 10 times) if it fails due to 5xx error or any other Fatal error;
- Automatically fixes the SSL issues with the PHP development server for WordPress environment;
- Custom .htaccess file rules ensures the basic handling of WP admin panel rewrite rules (like /plugins.php will be converted to /wp-admin/plugins.php). However, there might be some edge cases where the user will need to manually add "/wp-admin/" prefix for the PHP development server to not throw an error 404.

### How to use it?
Just [connect to your hosting plan via SSH](https://support.hostinger.com/en/articles/1583245-how-to-connect-to-a-hosting-plan-via-ssh "connect to your hosting plan via SSH"),  navigate to your WordPress website's root directory (usually public_html folder) and run this command:
```bash
curl -s https://raw.githubusercontent.com/Laury8nas/litespeed_connection_bypass/refs/heads/main/php_script.sh > php_script.sh && chmod +x php_script.sh && ./php_script.sh
```
Keep in mind that the bypassing scheme works **only for one website on a hosting plan at once**! If you need to change the website for which you want to bypass the connection timeout limit, you need to stop the existing processes by running the script again on the previously selected website's root directory and selecting option 2  ("2. Revert changes").

### Responsibility
I want to highlight the fact that this is a fully experimental project and bugs may happen, so **you are always responsible** for making sure that you have a reliable backup created before doing any of these actions. I'm not responsible for any data loss, website integrity problems or any other damage that you might have by using this bash script. Good luck & have fun!
