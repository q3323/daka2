# Daka Official Website

Minimal official download page for the Daka HarmonyOS app.

## Configure

Edit `app.js`:

```js
const siteConfig = {
  downloadUrl: "./downloads/daka.hap",
  icpNumber: "粤ICP备2026171342号-1"
};
```

Put the signed package at `downloads/daka.hap`. When `downloadUrl` is empty,
the page displays `安装包准备中`.

## Deploy

```bash
sudo mkdir -p /var/www/daka
sudo cp -a web/. /var/www/daka/
sudo chown -R www-data:www-data /var/www/daka
```

In the HTTPS Nginx server block, serve static files for the root and keep
proxying API requests to Node:

```nginx
root /var/www/daka;
index index.html;

location /api/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location = /health {
    proxy_pass http://127.0.0.1:3000/health;
}

location / {
    try_files $uri $uri/ /index.html;
}
```

Do not replace the existing HTTPS certificate paths written by Certbot.
