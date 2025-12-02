#!/bin/bash

SERVICE=${1:-backend}

podman-compose -f podman-compose.yml logs -f $SERVICE
