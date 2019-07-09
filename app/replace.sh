#!/usr/bin/env bash

UPSTREAM_URL="${UPSTREAM_URL:-http://wordpress}"
sed s,'${UPSTREAM_URL}',"${UPSTREAM_URL}",g < nginx.template.conf > nginx.conf
