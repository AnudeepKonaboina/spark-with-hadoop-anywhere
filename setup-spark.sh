#!/usr/bin/env bash

# =============================================================================
# Spark with Hadoop Setup Script
# =============================================================================
# Description: Sets up Spark 3.4.1 with Hadoop 3.3.6 and Hive 3.1.3
# Requirements: Docker, Docker Compose
# 
# Usage:
#   ./setup-spark.sh --run              # Pull images from DockerHub
#   ./setup-spark.sh --build --run      # Build images locally
#
# Components:
#   - Java 8 
#   - Spark 3.4.1 (Scala 2.12)
#   - Hadoop 3.3.6
#   - Hive 3.1.3
#   - PostgreSQL metastore
# =============================================================================

set -eo pipefail

# -----------------------------------------------------------------------------
# Parse command line arguments
# -----------------------------------------------------------------------------
BUILD_MODE=false
RUN_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --build)
      BUILD_MODE=true
      shift
      ;;
    --run)
      RUN_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--build] [--run]"
      echo "  --run         : Pull images from DockerHub and run..a quick way to setup"
      echo "  --build --run : Build images locally and run"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ "$BUILD_MODE" = false ] && [ "$RUN_MODE" = false ]; then
  echo "Error: Please specify --run or --build --run"
  echo "Usage: $0 [--build] [--run]"
  echo "  --run         : Pull images from Docker Hub and run"
  echo "  --build --run : Build images locally and run"
  exit 1
fi

if [ "$BUILD_MODE" = true ] && [ "$RUN_MODE" = false ]; then
  echo "Error: --build must be used with --run"
  echo "Usage: $0 --build --run"
  exit 1
fi

# -----------------------------------------------------------------------------
# Build or Pull images
# -----------------------------------------------------------------------------
if [ "$BUILD_MODE" = true ]; then
  echo "=================================================="
  echo "Building images locally..."
  echo "=================================================="
  
  # Build with local tag
  docker build -t hive-metastore:local \
    -f hive-metastore/Dockerfile .
  
  docker build -t spark-with-hadoop:local \
    -f spark-hadoop-standalone/Dockerfile .
  
  echo "Build complete!"
  
  # Set environment variables to use local images
  export HIVE_METASTORE_IMAGE="hive-metastore:local"
  export SPARK_HADOOP_IMAGE="spark-with-hadoop:local"
else
  echo "=================================================="
  echo "Pulling images from Docker Hub..."
  echo "=================================================="
  
  docker pull docker4ops/hive-metastore:hive-3.1.3
  docker pull docker4ops/spark-with-hadoop:spark-3.4.1_hadoop-3.3.6_hive-3.1.3
  
  echo "Pull complete!"
  
  # Set environment variables to use Docker Hub images (default)
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-3.1.3"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-3.4.1_hadoop-3.3.6_hive-3.1.3"
fi


# -----------------------------------------------------------------------------
# Start services
# -----------------------------------------------------------------------------
echo ""
echo "=================================================="
echo "Starting services with:"
echo "  Hive Metastore: $HIVE_METASTORE_IMAGE"
echo "  Spark Hadoop  : $SPARK_HADOOP_IMAGE"
echo "=================================================="
docker-compose up -d

echo ""
echo "Waiting for containers to be ready..."
sleep 10

# Initialize HDFS and Hive warehouse dirs

docker exec spark bash -lc '
  hdfs namenode -format -force &&
  start-dfs.sh &&
  sleep 5 &&
  hdfs dfs -mkdir -p /tmp &&
  hdfs dfs -mkdir -p /user/hive/warehouse &&
  hdfs dfs -chmod g+w /user/hive/warehouse
' 2>&1 | grep -v "warning: setlocale" || true

# Start Hive Metastore (background) then HiveServer2
echo "Starting Hive services..."
docker exec -d spark bash -lc '
  hive --service metastore &
  sleep 15
  hive --service hiveserver2
' 2>&1 | grep -v "warning: setlocale" || true

# Simple Hive test after 15 seconds
echo "Waiting 15 seconds, then testing all services..."
HIVE_OK=false
if docker exec spark bash -lc 'sleep 15 && hive -e "show databases;" >/dev/null 2>&1'; then
  HIVE_OK=true
fi

# Post-wait quick checks for all services
HDFS_OK=false
SPARK_OK=false

# HDFS quick check
if docker exec spark bash -lc 'ps aux | grep -q "org.apache.hadoop.hdfs.server.namenode.NameNode" && ps aux | grep -q "org.apache.hadoop.hdfs.server.datanode.DataNode"'; then
  HDFS_OK=true
else
  docker exec spark bash -lc 'timeout 10s hdfs dfs -ls / >/dev/null 2>&1' && HDFS_OK=true || true
fi

# Spark quick version check
docker exec spark bash -lc 'timeout 10s spark-submit --version >/dev/null 2>&1' && SPARK_OK=true || true

echo ""
if [ "$HIVE_OK" = true ] && [ "$HDFS_OK" = true ] && [ "$SPARK_OK" = true ]; then
  echo "============================================================"
  echo "[+] Spark with Hadoop setup completed successfully !"
  echo "============================================================"
  echo ""
  echo "[+] Run the following command to connect to the Spark container:"
  echo "    docker exec -it spark bash"
  echo ""
  echo "[+] Run the following commands to start the following services:"
  echo "  - Spark Shell: spark-shell"
  echo "  - PySpark    : pyspark"
  echo "  - Hive       : hive"
  echo "  - Beeline    : beeline"
  echo "  - HDFS       : hdfs dfs -ls /"
  echo ""
  echo "============================================================"
else
  echo ""
  echo "============================================================"
  echo "⚠ Some services are not fully ready yet"
  echo "============================================================"
  [ "$HIVE_OK" = true ] || echo "  ✗ Hive not ready"
  [ "$HDFS_OK" = true ] || echo "  ✗ HDFS not ready"
  [ "$SPARK_OK" = true ] || echo "  ✗ Spark not ready"
  echo ""
  echo "Check logs:"
  echo "  docker exec spark tail -50 /tmp/root/metastore.log"
  echo "  docker exec spark tail -50 /tmp/root/hiveserver2.log"
  echo "============================================================"
fi

