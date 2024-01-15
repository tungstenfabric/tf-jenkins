# Plane

Plane is the project management tool that can be used in place of Jira.

## Installation

The main process is described on https://docs.plane.so

Improvements:
1. Changed the following variables in docker-compose.yaml to:
```yaml
    - DATABASE_URL=${DATABASE_URL:-postgresql://plane:plane@plane-db/plane}
    - REDIS_URL=${REDIS_URL:-redis://plane-redis:6379}
```
(fixed the issue https://github.com/makeplane/plane/issues/3125)

2. Added to environment in docker-compose.yaml 
```yaml
    - VIRTUAL_HOST=<hostname>
    - VIRTUAL_PORT=80
    - LETSENCRYPT_HOST=<hostname>
    - LETSENCRYPT_EMAIL=<some email>
```
3. Added to services in docker-compose.yaml
```yaml
  nginx-proxy:
    container_name: nginx-proxy
    image: jwilder/nginx-proxy
    restart: unless-stopped
    ports:
      - 80:80
      - 443:443
    volumes:
      - conf:/etc/nginx/conf.d
      - vhost:/etc/nginx/vhost.d
      - html:/usr/share/nginx/html
      - dhparam:/etc/nginx/dhparam
      - certs:/etc/nginx/certs:ro
      - /var/run/docker.sock:/tmp/docker.sock:ro

  letsencrypt:
    container_name: letsencrypt
    image: jrcs/letsencrypt-nginx-proxy-companion
    environment:
      - NGINX_PROXY_CONTAINER=nginx-proxy
    volumes:
      - vhost:/etc/nginx/vhost.d
      - html:/usr/share/nginx/html
      - certs:/etc/nginx/certs:rw
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
```
and corresponding volumes:
```yaml
  conf:
  vhost:
  html:
  dhparam:
```

