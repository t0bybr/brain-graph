#!/bin/bash

SERVICE=${1:-backend}

docker-compose logs -f $SERVICE
