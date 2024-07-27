#!/bin/sh
# Author: Taki Elias
# OS Compatibility: Ubuntu 22.04

# Default values for parameters
DEFAULT_PHP_VERSION=8.3
DEFAULT_NODE_VERSION=18
DEFAULT_LARAVEL_VERSION=11
DEFAULT_DOMAIN="example.test"
DEFAULT_MYSQL_PASSWORD=$(openssl rand -base64 10)

# Initialize parameters with default values
PHP_VERSION=$DEFAULT_PHP_VERSION
NODE_VERSION=$DEFAULT_NODE_VERSION
MYSQL_PASSWORD=$DEFAULT_MYSQL_PASSWORD
LARAVEL=""
DOMAIN=""

# Function to display help text
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --domain=         Specify the domain (default: $DEFAULT_DOMAIN)"
  echo "  --php=            Specify the php version (default: $DEFAULT_PHP_VERSION)"
  echo "  --node=           Specify the NodeJS version (default: $DEFAULT_NODE_VERSION)"
  echo "  --laravel=        Specify the Laravel version (default: $DEFAULT_LARAVEL_VERSION)"
  echo "  --mysql-password= Specify the MySQL Password (default: Randomly generated)"
  echo "  --help            Display this help and exit"
}

# Parse the command line arguments
for arg in "$@"; do
  case $arg in
    --php=*)
    PHP_VERSION="${arg#*=}"
    shift # Remove --php= from processing
    ;;
    --node=*)
    NODE_VERSION="${arg#*=}"
    shift # Remove --node= from processing
    ;;
    --mysql-password=*)
    MYSQL_PASSWORD="${arg#*=}"
    shift # Remove --mysql-password= from processing
    ;;
	--domain=*)
    DOMAIN="${arg#*=}"
    shift # Remove --domain= from processing
    ;;
	--laravel=*)
    LARAVEL="${arg#*=}"
    shift # Remove --laravel= from processing
    ;;
    --help)
    show_help
    exit 0
    ;;
    *)
    echo "Unknown option: $arg"
    show_help
    exit 1
    ;;
  esac
done

if [ -z "$DOMAIN" ]; then
  read -p "Enter domain [default: $DEFAULT_DOMAIN]: " DOMAIN
  DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}
fi

if [ -z "$LARAVEL" ]; then
  read -p "Enter laravel [default: $DEFAULT_LARAVEL_VERSION]: " version
  LARAVEL=${LARAVEL:-$DEFAULT_LARAVEL_VERSION}
fi

# Configure mysql with random password
echo "mysql-server mysql-server/root_password password $MYSQL_PASSWORD" | sudo debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD" | sudo debconf-set-selections
echo $MYSQL_PASSWORD > /root/.mysql_password

sudo apt update -y
sudo apt upgrade -y

# Install common packages
sudo apt update -q && sudo apt install -yq \
    apt-utils software-properties-common \
    ca-certificates gnupg git zip unzip curl wget \
    nginx certbot python3-certbot-nginx \
    redis-server supervisor mysql-server firewalld

# Install PHP and extensions
sudo add-apt-repository -y ppa:ondrej/php
sudo apt install -yq \
    php$PHP_VERSION \
    php$PHP_VERSION-fpm \
    php$PHP_VERSION-mysql \
    php$PHP_VERSION-mbstring \
    php$PHP_VERSION-xml \
    php$PHP_VERSION-curl \
    php$PHP_VERSION-zip \
    php$PHP_VERSION-gd \
    php$PHP_VERSION-imagick \
    php$PHP_VERSION-bcmath \
    php$PHP_VERSION-redis \
    php$PHP_VERSION-intl \
    php$PHP_VERSION-soap \
    php$PHP_VERSION-sqlite3

sudo apt install -y php$PHP_VERSION-cli php$PHP_VERSION-pdo php$PHP_VERSION-iconv php$PHP_VERSION-simplexml php$PHP_VERSION-xmlreader nano php$PHP_VERSION-opcache php$PHP_VERSION-ffi git

# Install NodeJS
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update -q && sudo apt install -yq nodejs

# Enable & start php-fpm
sudo systemctl enable php$PHP_VERSION-fpm
sudo systemctl restart php$PHP_VERSION-fpm

# Add the MariaDB repository and install MariaDB server
sudo apt install -y mariadb-server

# Enable and start MariaDB
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Configure the firewall
sudo systemctl start firewalld
sudo systemctl enable firewalld
sudo firewall-cmd --permanent --add-service=mysql
sudo firewall-cmd --reload

# Create the directories:
sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled

# Back up existing config
sudo cp -R /etc/nginx /etc/nginx-backup
sudo chmod -R 755 /var/log
sudo chown -R www-data:www-data /usr/share/nginx/html
echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/index.php
sudo sed -i 's|;*user = www-data|user = www-data|g' /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
sudo sed -i 's|;*group = www-data|group = www-data|g' /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
sudo sed -i 's|;*pm = ondemand|pm = ondemand|g' /etc/php/$PHP_VERSION/fpm/pool.d/www.conf

# Configure PHP
sudo sed -i 's|;cgi.fix_pathinfo=1|cgi.fix_pathinfo=0|g' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's|;*expose_php=.*|expose_php=0|g' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's|; max_input_vars = 1000|max_input_vars = 5000|g' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's|;*post_max_size = 8M|post_max_size = 100M|g' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's|;*upload_max_filesize = 2M|upload_max_filesize = 100M|g' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's|;*max_file_uploads = 20|max_file_uploads = 20|g' /etc/php/$PHP_VERSION/fpm/php.ini

# Remove default
sudo rm /etc/nginx/sites-available/default
sudo rm /etc/nginx/sites-enabled/default

# Create nginx.conf
cat << 'EOF' > /etc/nginx/$DOMAIN.conf
#user  nobody;
worker_processes  1;

#pid        logs/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
    #                  '$status $body_bytes_sent "$http_referer" '
    #                  '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    ###################Reject slow request sending

    #keepalive_timeout  0;
    # Timeouts, do not keep connections open longer then necessary to reduce
    # resource usage and deny Slowloris type attacks.
    client_body_timeout      5s; # maximum time between packets the client can pause 
                                 # when sending nginx any data
    client_header_timeout    5s; # maximum time the client has to send the entire header to nginx
    keepalive_timeout       30s; # timeout which a single keep-alive client connection will stay open
    send_timeout            15s; # maximum time between packets nginx is allowed to pause 
                                 # when sending the client data

    ###################Limit connection per ip

    geo $whitelist {
       default          0;
       # CIDR in the list below are not limited
       1.2.3.0/24       1;
       9.10.11.12/32    1;
       # All private IP ranges
       127.0.0.1/32     1;
       10.0.0.0/8       1;
       172.16.0.0/12    1;
       192.168.0.0/16   1;
    }
    map $whitelist $limit {
        0     $binary_remote_addr;
        1     "";
    }
    # The directives below limit concurrent connections from a
    # non-whitelisted IP address
    limit_conn_zone      $limit    zone=connlimit:10m;
    limit_conn           connlimit 20;
    limit_conn_log_level warn;   # logging level when threshold exceeded
    limit_conn_status    503;    # the error code to return

    # Allow N req/sec to non-whitelisted IPs with a burst of another 10.
    limit_req_zone       $limit   zone=one:10m  rate=50r/s;
    limit_req            zone=one burst=10;
    limit_req_log_level  warn;
    limit_req_status     503;

    ################### Block large POST ###################
    client_max_body_size 128M;
    client_body_buffer_size    1024k;
    client_body_in_single_buffer on;
    client_header_buffer_size    1k;
    large_client_header_buffers  4 4k;

    ### Nginx Conf Includes

    include /etc/nginx/sites-enabled/*;

    #gzip  on;

}

EOF

# Create the default conf file
cat <<EOT > /etc/nginx/sites-available/$DOMAIN.conf
server { 
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN;

    root /usr/share/nginx/html/$DOMAIN/public;
    index index.php index.html index.htm;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block"; 
    add_header X-Content-Type-Options "nosniff"; 
    client_max_body_size 128M; 
    charset utf-8;

    location / { 
        try_files \$uri \$uri/ /index.php?\$args; 
    }
    location = /favicon.ico { 
        access_log off; 
        log_not_found off; 
    } 
    location = /robots.txt { 
        access_log off; 
        log_not_found off; 
    } 

    error_page 404 /index.php;

    location ~ /wp-admin/load-(scripts|styles).php { 
        deny all;
    }
    location ~ [^/]\.php(/|$) { 
        fastcgi_split_path_info ^(.+\.php)(/.+)$; 
        fastcgi_index index.php; 
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock; 
        include fastcgi_params; 
        fastcgi_param PATH_INFO \$fastcgi_path_info; 
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        #For deployer
        #fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
    }
    location ~ /\.(?!well-known).* { 
        deny all;
    }

    error_log /var/log/nginx/$DOMAIN.error.log warn;

}

EOT

# Symbolic link to the configuration
sudo ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/

# Modify PHP-FPM to use www-data user and group
sudo sed -i 's/user = www-data/user = www-data/g' /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
sudo sed -i 's/group = www-data/group = www-data/g' /etc/php/$PHP_VERSION/fpm/pool.d/www.conf

for i in nginx php$PHP_VERSION-fpm; do sudo systemctl enable $i --now; done
for i in nginx php$PHP_VERSION-fpm; do sudo systemctl restart $i; done

# Download and install Composer
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Create a new Laravel application
cd /usr/share/nginx/html
composer create-project --prefer-dist laravel/laravel laravel "$LARAVEL.*" || { echo "Laravel installation failed"; exit 1; }

# Set proper file permissions
sudo chown -R www-data:www-data /usr/share/nginx/html/$DOMAIN

# Set proper file permissions for Laravel
sudo chmod -R 755 /usr/share/nginx/html/$DOMAIN/storage
sudo chmod -R 755 /usr/share/nginx/html/$DOMAIN/bootstrap/cache

# Ensure that your firewall is allowing HTTP (port 80) and HTTPS (port 443) traffic
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Restart Nginx and PHP-FPM
sudo systemctl restart nginx
sudo systemctl restart php$PHP_VERSION-fpm

# Proper Permission for MySQL
sudo usermod -a -G mysql www-data
sudo chmod 770 /var/run/mysqld/mysqld.sock

echo "Deployment completed successfully"
