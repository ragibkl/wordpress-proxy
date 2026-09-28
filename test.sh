#!/usr/bin/env bash
# Behaviour tests for the proxy config, against the docker-compose stack.
#
#   docker compose -p wpp-test up -d
#   ./test.sh fresh    # new WordPress: install it through the proxy (first time only)
#   ./test.sh setup    # permalinks + a cookie-setting test plugin (first time only)
#   ./test.sh
#
# The test plugin sets a cookie on every public page, like the popup and
# visitor-counter plugins on real sites do.
set -uo pipefail

P=${COMPOSE_PROJECT:-wpp-test}
URL=http://localhost:8080
PASS=0; FAIL=0

dc() { docker compose -p "$P" "$@"; }
wp() {
  docker run --rm --network "${P}_default" -v "${P}_wordpress:/var/www/html" --user 33:33 \
    -e WORDPRESS_DB_HOST=mariadb -e WORDPRESS_DB_NAME=wordpress \
    -e WORDPRESS_DB_USER=wordpress -e WORDPRESS_DB_PASSWORD=change-me \
    wordpress:cli wp "$@"
}

has() {  # has <pattern> <text>: pattern found? (no pipes: pipefail + grep -q misreport)
  if [[ "$2" == *"$1"* ]]; then echo yes; else echo no; fi
}
check() {  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok    $1"
  else FAIL=$((FAIL+1)); echo "FAIL  $1: expected '$2', got '$3'"; fi
}
# req [curl args...] -> "<status> <X-Cache-Status> <cookie:yes|no>"
req() {
  local h; h=$(curl -s -o /dev/null -D - "$@")
  local status cache cookie
  status=$(printf '%s' "$h" | awk 'NR==1{print $2}')
  cache=$(printf '%s' "$h" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-cache-status"{print $2}')
  cookie=$(has $'\nset-cookie:' "${h,,}")
  echo "$status ${cache:--} $cookie"
}
u() { echo "$URL/$1-$RANDOM$RANDOM/"; }  # a fresh uncached path

wait_for() {  # wait_for <seconds> <what> <command...>: bounded, so CI can't hang
  local deadline=$((SECONDS + $1)) what=$2; shift 2
  until "$@" >/dev/null 2>&1; do
    if [ $SECONDS -ge $deadline ]; then echo "timed out waiting for $what"; exit 1; fi
    sleep 2
  done
}
done_() { echo; echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; exit; }

wait_for 60 "the proxy" curl -sf -o /dev/null "$URL/healthz"

if [ "${1:-}" = fresh ]; then
  # A brand-new WordPress, installed through the proxy like a browser would.
  wait_for 180 "WordPress to reach its database" \
    bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code}' $URL/) == 30[12] ]]"
  echo "# fresh install"
  check "uninstalled site redirects to the installer" "302 yes" \
    "$(req "$URL/" | awk '{print $1}') $(has 'wp-admin/install.php' "$(curl -s -o /dev/null -w '%{redirect_url}' "$URL/")")"
  check "...and that redirect is not cached" "302 MISS" "$(req "$URL/" | awk '{print $1, $2}')"
  check "installer bypasses the cache" "200 BYPASS" "$(req "$URL/wp-admin/install.php" | awk '{print $1, $2}')"
  body=$(curl -s "$URL/wp-admin/install.php?step=2" \
    --data-urlencode weblog_title="Proxy Test" --data-urlencode user_name=admin \
    --data-urlencode admin_password=testpass123 --data-urlencode admin_password2=testpass123 \
    --data-urlencode pw_weak=1 --data-urlencode admin_email=admin@example.com \
    --data-urlencode blog_public=0 --data-urlencode Submit="Install WordPress")
  check "install through the proxy succeeds" "yes" "$(has 'Success!' "$body")"
  check "installed site serves the front page, not a cached redirect" "200" "$(req "$URL/" | awk '{print $1}')"
  done_
fi

if [ "${1:-}" = setup ]; then
  # Pretty permalinks and a plugin that sets a cookie on every public page.
  # Installs WordPress too if `fresh` hasn't.
  wait_for 180 "the database" wp db check
  wp core is-installed || wp core install --url="$URL" --title="Proxy Test" --admin_user=admin \
    --admin_password=testpass123 --admin_email=admin@example.com --skip-email
  wp option update permalink_structure '/%postname%/'
  # wp-cli can't tell Apache has mod_rewrite, so --hard would write an empty
  # .htaccess block (and a browser install leaves one): every pretty URL 404s.
  wp eval 'file_put_contents(ABSPATH . "wp-cli.yml", "apache_modules:\n  - mod_rewrite\n");'
  wp rewrite flush --hard
  wp eval 'wp_mkdir_p(WP_CONTENT_DIR . "/mu-plugins"); file_put_contents(WP_CONTENT_DIR . "/mu-plugins/test-cookie.php", "<?php\nadd_action(\"init\", function () { if (!is_admin()) setcookie(\"test_popup\", \"seen\", 0, \"/\"); });\n");'
  exit
fi

echo "# proxy"
check "healthz answers without WordPress" "200" "$(curl -s -o /dev/null -w '%{http_code}' "$URL/healthz")"

echo "# caching"
p="$URL/"
req "$p" >/dev/null
check "front page is cached" "200 HIT no" "$(req "$p")"
check "cached response carries no Set-Cookie" "no" "$(req "$p" | awk '{print $3}')"
check "backend does set the cookie (so stripping is real)" "yes" \
  "$(has 'Set-Cookie: test_popup' "$(dc exec -T wordpress-proxy sh -c 'wget -S -q -O /dev/null --header="Host: localhost:8080" http://wordpress/ 2>&1')")"
check "404 is cached briefly" "404 HIT no" "$(x=$(u missing); req "$x" >/dev/null; req "$x")"
a=$(curl -s "$URL/" | grep -o 'wp-includes/[^"]*\.js?ver=[^"]*' | head -1)
req "$URL/$a" >/dev/null
check "static asset with ?ver= is cached" "200 HIT" "$(req "$URL/$a" | awk '{print $1, $2}')"

echo "# bypass"
check "query string bypasses" "200 BYPASS" "$(req "$URL/?s=hello" | awk '{print $1, $2}')"
check "POST bypasses" "BYPASS" "$(req -X POST "$URL/" | awk '{print $2}')"
check "wp-login.php bypasses and keeps cookies" "200 BYPASS yes" "$(req "$URL/wp-login.php")"
jar=$(mktemp)
curl -s -o /dev/null -c "$jar" -b "$jar" "$URL/wp-login.php"
curl -s -o /dev/null -c "$jar" -b "$jar" -d 'log=admin&pwd=testpass123&wp-submit=Log+In&testcookie=1' "$URL/wp-login.php"
check "login sets wordpress_logged_in" "yes" "$(has wordpress_logged_in "$(cat "$jar")")"
check "logged-in user bypasses the cache" "200 BYPASS" "$(req -b "$jar" "$URL/" | awk '{print $1, $2}')"
check "logged-in user gets the admin bar" "yes" "$(has wpadminbar "$(curl -s -b "$jar" "$URL/")")"
check "anonymous user never gets the admin bar" "no" "$(has wpadminbar "$(curl -s "$URL/")")"
rm -f "$jar"

echo "# cache poisoning"
x=$(wp post create --post_status=publish --post_title="poison $RANDOM" --porcelain | tr -d '\r')
x=$(wp post list --post__in="$x" --field=url | tr -d '\r')   # a real page, never requested
check "unknown Host gets WordPress's redirect" "301" "$(req -H 'Host: evil.example' "$x" | awk '{print $1}')"
check "...which is not cached for the real host" "200 MISS" "$(req "$x" | awk '{print $1, $2}')"
check "request without https proto doesn't replace the https page" "200 HIT" \
  "$(req -H 'X-Forwarded-Proto: https' "$URL/" >/dev/null; req -H 'X-Forwarded-Proto: http' "$URL/" >/dev/null; req -H 'X-Forwarded-Proto: https' "$URL/" | awk '{print $1, $2}')"
check "redirects are never cached" "301 MISS" \
  "$(req -H 'Host: evil.example' "$URL/" >/dev/null; req -H 'Host: evil.example' "$URL/" | awk '{print $1, $2}')"

echo "# WordPress down"
req "$URL/" >/dev/null
dc stop wordpress >/dev/null 2>&1
check "cached page still served while WordPress is down" "200" "$(req "$URL/" | awk '{print $1}')"
t0=$SECONDS; code=$(req "$(u down)" | awk '{print $1}')
check "uncached page fails fast (5xx, <10s) while WordPress is down" "5xx fast" \
  "$([[ $code == 5* ]] && echo 5xx || echo "$code") $([ $((SECONDS-t0)) -lt 10 ] && echo fast || echo "slow($((SECONDS-t0))s)")"
dc start wordpress >/dev/null 2>&1

echo "# upstream re-resolution"
old=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${P}-wordpress-1")
dc stop wordpress >/dev/null 2>&1
docker run -d --rm --name "${P}-ip-squatter" --network "${P}_default" nginx:1.29-alpine sleep 60 >/dev/null
dc start wordpress >/dev/null 2>&1
new=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${P}-wordpress-1")
docker rm -f "${P}-ip-squatter" >/dev/null
check "WordPress came back on a new IP" "changed" "$([ "$old" != "$new" ] && echo changed || echo "same ($old)")"
sleep 11  # resolver valid=10s
check "proxy reaches WordPress at its new IP without a restart" "200" \
  "$(for i in 1 2 3 4 5; do c=$(curl -s -o /dev/null -w '%{http_code}' "$URL/?reresolve=$RANDOM"); [ "$c" = 200 ] && break; sleep 2; done; echo "$c")"

done_
