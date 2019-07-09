#!/usr/bin/env bash

TAG=${1:-latest}

docker build --pull -t ragibkl/wordpress-proxy:$TAG .
docker push ragibkl/wordpress-proxy:$TAG
