FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html style.css charts.js glass.js releases.js favicon.svg /usr/share/nginx/html/
COPY images/ /usr/share/nginx/html/images/

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1/healthz || exit 1
