#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Build images
# -----------------------------------------------------------------------------
#docker build -t hive-metastore:latest \
  -f hive-metastore/Dockerfile .

#docker build -t spark-with-hadoop-hive:latest \
  -f spark-hadoop-standalone/Dockerfile .

# -----------------------------------------------------------------------------
# Start services
# -----------------------------------------------------------------------------
docker-compose up -d

# Initialize HDFS and Hive warehouse dirs
docker exec -it spark bash -lc '
  hdfs namenode -format &&
  start-dfs.sh &&
  hdfs dfs -mkdir -p /tmp &&
  hdfs dfs -mkdir -p /user/hive/warehouse &&
  hdfs dfs -chmod g+w /user/hive/warehouse
'

# Start Hive Metastore (background) then HiveServer2
docker exec -d spark bash -lc '
  hive --service metastore &
  sleep 15
  hive --service hiveserver2
'
