#!/usr/bin/env bash

UPSTREAM_URL="${UPSTREAM_URL:-http://wordpress}"

cat nginx.template.conf \
    | sed s,'${UPSTREAM_URL}',"${UPSTREAM_URL}",g \
    > nginx.conf
