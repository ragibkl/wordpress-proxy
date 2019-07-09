#!/usr/bin/env bash

docker-compose down

cd app
./replace.sh

cd ..
docker-compose up -d
