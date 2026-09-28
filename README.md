# Wordpress Proxy

A drop-in caching layer for WordPress: one nginx config file for the
**official `nginx` image**. No custom image to build.

## Description

![architecture](docs/architecture.drawio.png)

A typical WordPress site generates every page dynamically from PHP and MySQL.
With a few plugins and a complex theme, that takes a noticeable time per page.
Wordpress Proxy sits in front of WordPress and caches pages for anonymous
visitors, so repeat visits are served by nginx in milliseconds.

It also keeps serving cached pages while WordPress or its database is down or
erroring. That keeps the site up, but it also hides the outage: monitor the
WordPress backend directly, not just the public URL.

## Usage

Everything is in [`templates/default.conf.template`](templates/default.conf.template).
The official nginx image renders `/etc/nginx/templates/*.template` on startup,
substituting environment variables, so you only need to mount the directory
and set two variables:

| Variable | Value |
| --- | --- |
| `UPSTREAM_URL` | Base URL of the WordPress site, e.g. `http://wordpress` |
| `NGINX_ENTRYPOINT_LOCAL_RESOLVERS` | `1`: lets nginx re-resolve `UPSTREAM_URL` (a recreated container gets a new IP) using the Docker or cluster DNS from `/etc/resolv.conf` |

### Docker Compose

[`docker-compose.yml`](docker-compose.yml) is a complete example (proxy,
WordPress, MariaDB). To put the proxy in front of an existing WordPress, you
only need this service and the `templates` directory:

```yaml
services:
  wordpress-proxy:
    image: nginx:1.29-alpine
    ports:
      - 80:80
    environment:
      UPSTREAM_URL: http://wordpress
      NGINX_ENTRYPOINT_LOCAL_RESOLVERS: "1"
    volumes:
      - ./templates:/etc/nginx/templates:ro
```

### Kubernetes

[`k8s/wordpress-proxy.yaml`](k8s/wordpress-proxy.yaml) is a Deployment and
Service with the template mounted from a ConfigMap:

```bash
kubectl create configmap wordpress-proxy-templates \
  --from-file=templates/default.conf.template
kubectl apply -f k8s/wordpress-proxy.yaml
```

Point your Ingress at the `wordpress-proxy` Service. It must pass the real
`Host` and `X-Forwarded-Proto` headers (ingress-nginx does by default).

## Behaviour

- **Cached:** anonymous `GET`/`HEAD` requests for pages (200s for 5 minutes,
  404s for 1 minute) and static assets (also with `?ver=`). The cache key is
  scheme + host + URI.
- **Never cached:** redirects and errors; logged-in users and recent
  commenters (by cookie); `wp-admin`, `wp-json`, logins, `xmlrpc.php`, feeds,
  sitemaps, WooCommerce cart/checkout/account; any query string; any method
  but `GET`/`HEAD`. These go straight to WordPress with cookies intact.
- **`Set-Cookie` is stripped from cached responses**, so one visitor's cookie
  is never served to everyone. Plugins that must set cookies for anonymous
  visitors need their pages on the never-cached list.
- **Stale pages** are served while a page is refreshed in the background, and
  while WordPress is down or returning 5xx.
- **`X-Cache-Status`** response header: `HIT`, `MISS`, `STALE`, `UPDATING`,
  or `BYPASS`.
- **`/healthz`** is answered by nginx itself, for probes.

There is no purge: after editing content, anonymous visitors see the update
within 5 minutes.

## Testing

[`test.sh`](test.sh) checks all of the above against the compose stack,
including cache poisoning (unknown hosts, wrong scheme), serving stale pages
with WordPress stopped, and re-resolving WordPress on a new IP:

```bash
docker compose -p wpp-test up -d
./test.sh setup   # first time: installs WordPress and a cookie-setting test plugin
./test.sh
docker compose -p wpp-test down -v
```

## Upgrading from the `ragibkl/wordpress-proxy` image

The Docker Hub image (OpenResty, last built 2022) is deprecated. Replace it with
`nginx:<version>` plus the template, as above. Differences from the old
config:

- The cache key includes the host and scheme, and only 200/404 responses are
  cached. The old config cached redirects under a key without the host, so a
  single request with the wrong `Host` or scheme could put a redirect loop in
  front of every visitor.
- `Set-Cookie` is stripped from cached responses instead of being cached and
  served to everyone.
- `X-Forwarded-Proto` is set explicitly instead of relying on it being passed
  through.
- Pages are cached for 5 minutes instead of 15, and failures to reach
  WordPress time out in 5 seconds instead of 60.
