map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

# Setup load balancer Local IP addresses for HTTPS connections
upstream https-backend {
    server [LOCAL IP]:35997; #local node
    server [LOCAL IP]:35997; #local node
    #sticky route $route_cookie $route_uri;
    }

# Setup load balancer Local IP addresses for WSS connections
upstream wss-backend {
    server [LOCAL IP]:35998; #local node
    server [LOCAL IP]:35998; #local node
    keepalive 1000;
}

# Server block to redirect port 80 requests to port 443
server {
    listen 80;
    server_name secure.deeznnodez.com;

    if ($host = secure.deeznnodez.com) {
        return 301 https://$host$request_uri;
        } # managed by Certbot

    return 404; # managed by Certbot
    }

# Server block to renew SSL certs by letsencrypt  DO NOT REMOVE
server {
    listen 443 ssl; # managed by Certbot
    server_name secure.deeznnodez.com;
    root /var/www/secure.deeznnodez.com/html;
    index index.html;
    ssl_certificate /etc/letsencrypt/live/secure.deeznnodez.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/secure.deeznnodez.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

    location / {
        try_files $uri $uri/ =404;
        }
    }

# Server block for https connections to port 35997 for API calls
server {
    listen 35997 ssl;
    server_name secure.deeznnodez.com;
    ssl_certificate /etc/letsencrypt/live/secure.deeznnodez.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/secure.deeznnodez.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

    location / {
        #proxy_pass http://https-backend; upstream not used because of NGINX config issue
        proxy_pass http://[LOCAL IP]:35997; #using one local node rather than load balancer. See note above
        }
    }

# Server block for wss connections to port 35997 for secure websocket calls
server {
    listen 35998 ssl;
    server_name secure.deeznnodez.com;
    ssl_certificate /etc/letsencrypt/live/secure.deeznnodez.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/secure.deeznnodez.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
    ssl_verify_client off;

    location / {
      proxy_http_version 1.1;
      proxy_pass http://wss-backend;
      proxy_redirect off;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_read_timeout 3600s;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
    }
}
