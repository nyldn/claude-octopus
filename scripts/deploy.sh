#!/usr/bin/env bash
# Wrapper script - validates and deploys plugin/ subdirectory
cd "$(dirname "$0")/plugin" && ./deploy.sh
