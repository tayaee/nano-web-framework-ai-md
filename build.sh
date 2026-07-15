#!/bin/bash
mkdir -p logs > NUL 2>&1
echo [DEBUG] docker compose build
docker compose build | tee logs/build.log
