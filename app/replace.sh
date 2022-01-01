#!/usr/bin/env bash

UPSTREAM_URL="${UPSTREAM_URL:-http://wordpress}"
ENABLE_X_REAL_IP_HEADER="${ENABLE_X_REAL_IP_HEADER:-false}"
ENABLE_X_FORWARDED_FOR_HEADER="${ENABLE_X_FORWARDED_FOR_HEADER:-false}"

X_REAL_IP=""
if [[ $ENABLE_X_REAL_IP_HEADER = "true" ]]
then
    X_REAL_IP='proxy_set_header X-Real-IP $remote_addr;'
fi

X_FORWARDED_FOR=""
if [[ $ENABLE_X_FORWARDED_FOR_HEADER = "true" ]]
then
    X_FORWARDED_FOR='proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;'
fi

cat nginx.template.conf \
    | sed s,'${UPSTREAM_URL}',"${UPSTREAM_URL}",g \
    | sed s,'${X_REAL_IP}',"${X_REAL_IP}",g \
    | sed s,'${X_FORWARDED_FOR}',"${X_FORWARDED_FOR}",g \
    > nginx.conf
