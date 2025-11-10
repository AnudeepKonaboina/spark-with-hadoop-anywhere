#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Parse command line arguments
# -----------------------------------------------------------------------------
BUILD_MODE=false
RUN_MODE=false

for arg in "$@"; do
  case $arg in
    --build)
      BUILD_MODE=true
      shift
      ;;
    --run)
      RUN_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--build] [--run]"
      echo "  --run         : Pull images from Docker Hub and run"
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
  
  docker pull docker4ops/hive-metastore:hive-2.1.1
  docker pull docker4ops/spark-with-hadoop:spark-2.4.7_hadoop-2.10.1_hive-2.1.1
  
  echo "Pull complete!"
  
  # Set environment variables to use Docker Hub images (default)
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-2.1.1"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-2.4.7_hadoop-2.10.1_hive-2.1.1"
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

# Initialize HDFS and Hive warehouse dirs
docker exec -i spark bash -lc '
  hdfs namenode -format -force &&
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

echo ""
echo "=================================================="
echo "[+] Setup complete!"
echo "=================================================="
echo ""
echo "[+]Run the following command to connect to the Spark container:"
echo "  docker exec -it spark bash"
echo ""
echo "[+] Run the following commands to start the following services:"
echo "  - Spark Shell: spark-shell"
echo "  - PySpark    : pyspark"
echo "  - Hive       : hive"
echo "  - Beeline    : beeline"
echo "  - HDFS       : hdfs dfs -ls /"
echo ""
echo "=================================================="

