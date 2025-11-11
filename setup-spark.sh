#!/usr/bin/env bash

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
  
  docker pull docker4ops/hive-metastore:hive-4.0.0
  docker pull docker4ops/spark-with-hadoop:spark-3.5.7_hadoop-3.3.6_hive-4.0.0
  
  echo "Pull complete!"
  
  # Set environment variables to use Docker Hub images (default)
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-4.0.0"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-3.5.7_hadoop-3.3.6_hive-4.0.0"
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

# Poll for containers to be running (max 60 seconds)
TIMEOUT=15
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  SPARK_STATUS=$(docker inspect -f '{{.State.Status}}' spark 2>/dev/null || echo "not_found")
  HIVE_STATUS=$(docker inspect -f '{{.State.Status}}' hive_metastore 2>/dev/null || echo "not_found")
  
  if [ "$SPARK_STATUS" = "running" ] && [ "$HIVE_STATUS" = "running" ]; then
    echo "✓ Containers are running"
    break
  fi
  
  echo "  Waiting... (${ELAPSED}s/${TIMEOUT}s) [spark: $SPARK_STATUS, hive: $HIVE_STATUS]"
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "⚠ Warning: Containers did not become ready within ${TIMEOUT}s"
  echo "Current status:"
  docker ps -a | grep -E "spark|hive_metastore"
fi

# Initialize HDFS and Hive warehouse dirs
docker exec spark bash -lc '
  hdfs namenode -format -force &&
  start-dfs.sh &&
  sleep 5 &&
  hdfs dfs -mkdir -p /tmp &&
  hdfs dfs -mkdir -p /user/hive/warehouse &&
  hdfs dfs -chmod g+w /user/hive/warehouse
' 2>&1 | grep -v -e "warning: setlocale" -e "namenode is running" -e "Stop it first" -e ".pid file is empty" || true

# Initialize Hive metastore schema (required for Hive 4.0.0)
echo "Initializing Hive metastore schema..."
docker exec spark bash -lc 'schematool -dbType postgres -initSchema' 2>&1 | grep -E "Initialization script|completed|SUCCESS|FAILED" || true

# Start Hive Metastore (background) then HiveServer2 (silently)
docker exec -d spark bash -lc '
  hive --service metastore &
  sleep 15
  hive --service hiveserver2
' 2>&1 | grep -v "warning: setlocale" || true

echo ""
echo "============================================================"
echo "[+] Spark with Hadoop setup completed successfully !"
echo "============================================================"
echo ""
echo "[+] Run the following command to connect to the Spark container:"
echo "  docker exec -it spark bash"
echo ""
echo "[+] Run the following commands to start the following services:"
echo "  - Spark Shell: spark-shell"
echo "  - PySpark    : pyspark"
echo "  - Hive       : hive"
echo "  - Beeline    : beeline"
echo "  - HDFS       : hdfs dfs -ls /"
echo ""
echo "============================================================"
