#!/usr/bin/env bash

# =============================================================================
# Spark with Hadoop Setup Script
# =============================================================================
# Description: Sets up Spark 2.4.7 with Hadoop 2.10.1 and Hive 2.1.1
# Requirements: Docker, Docker Compose
# 
# Usage:
#   ./setup-spark.sh --run              # Pull images from DockerHub
#   ./setup-spark.sh --build --run      # Build images locally
#
# Components:
#   - Java 8 
#   - Spark 2.4.7 (Scala 2.11)
#   - Hadoop 2.10.1
#   - Hive 2.1.1
#   - PostgreSQL metastore
# =============================================================================

set -euo pipefail
if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script requires bash. Run: bash $0 [--build] [--run] [--node-type single|multi]"
  exit 1
fi

# -----------------------------------------------------------------------------
# Parse command line arguments
# -----------------------------------------------------------------------------
BUILD_MODE=false
RUN_MODE=false
STOP_MODE=false
MODE="single" # single | multi

while [ $# -gt 0 ]; do
  case "$1" in
    --build)
      BUILD_MODE=true
      shift
      ;;
    --run)
      RUN_MODE=true
      shift
      ;;
    --stop)
      STOP_MODE=true
      shift
      ;;
    --node-type=*)
      MODE="${1#*=}"
      shift
      ;;
    --node-type)
      if [ "${2:-}" = "" ]; then
        echo "Error: --node-type requires a value: single|multi"
        exit 1
      fi
      MODE="$2"
      shift 2
      ;;
    --single)
      MODE="single"
      shift
      ;;
    --multi)
      MODE="multi"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--build] [--run] [--stop] [--node-type single|multi]"
      echo "  --run                 : Pull images from Docker Hub and run(preferred)"
      echo "  --build --run         : Build images locally and run"
      echo "  --stop                : Stop and remove the selected stack"
      echo " Optional arguments:"
      echo "  --node-type single    : Single container/Single node cluster(default)"
      echo "  --node-type multi     : Spark master + workers containers/Multi node cluster"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ "$BUILD_MODE" = false ] && [ "$RUN_MODE" = false ] && [ "$STOP_MODE" = false ]; then
  echo "Error: Please specify --run or --build --run or --stop"
  echo "Usage: $0 [--build] [--run] [--stop] [--node-type single|multi]"
  echo "  --run                 : Pull images from Docker Hub and run(preferred)"
  echo "  --build --run         : Build images locally and run"
  echo "  --stop                : Stop and remove the selected stack"
  echo " Optional arguments:"
  echo "  --node-type single    : Single container/Single node cluster(default)"
  echo "  --node-type multi     : Spark master + workers cluster/Multi node cluster"
  exit 1
fi

if [ "$BUILD_MODE" = true ] && [ "$RUN_MODE" = false ]; then
  echo "Error: --build must be used with --run"
  echo "Usage: $0 --build --run"
  exit 1
fi

# -----------------------------------------------------------------------------
# Early stop: select compose file and bring the stack down
# -----------------------------------------------------------------------------
if [ "$STOP_MODE" = true ]; then
  echo ""
  echo "=================================================="
  echo "Stopping services (auto-detected):"
  echo "=================================================="
  # Auto-detect running stack by container names
  if docker ps --format '{{.Names}}' | grep -q '^spark$'; then
    echo "[single] Detected 'spark' container. Bringing down docker-compose.single.yml..."
    docker-compose -f "docker-compose.single.yml" down
  elif docker ps --format '{{.Names}}' | grep -q '^spark-master$'; then
    echo "[multi] Detected 'spark-master' container. Bringing down docker-compose.yml..."
    docker-compose -f "docker-compose.yml" down
  else
    echo "No known containers running (spark or spark-master). Attempting best-effort stop on both stacks..."
    docker-compose -f "docker-compose.single.yml" down || true
    docker-compose -f "docker-compose.yml" down || true
  fi
  echo ""
  echo "Removing all Docker images (this may take a while)..."
  # Remove all images; ignore errors if none exist
  docker rmi -f $(docker images -a -q) >/dev/null 2>&1 || true
  echo "Pruning Docker system (networks, caches, etc.)..."
  docker system prune -f >/dev/null 2>&1 || true
  echo "Done."
  exit 0
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
# Health check helper
# -----------------------------------------------------------------------------
health_check() {
  local container="$1"
  echo "Waiting 10 seconds for containers to completely start before health checks..."
  sleep 10
  echo "Starting health checks..."
  local HDFS_OK=false
  local SPARK_OK=false
  local HIVE_OK=false
  # Self-heal HDFS (multi-node) if NN is not reachable or has incompatible layout; no image rebuild needed
  if [ "$container" = "spark-master" ]; then
    docker exec "$container" bash -lc '
      if ! hdfs dfsadmin -safemode get >/dev/null 2>&1; then
        export HDFS_NAMENODE_USER=root HDFS_DATANODE_USER=root HDFS_SECONDARYNAMENODE_USER=root
        (stop-dfs.sh || true) >/dev/null 2>&1 || true
        rm -rf /usr/bin/data/nameNode/* /usr/bin/data/nameNodeSecondary/* /usr/bin/data/dataNode/* || true
        hdfs namenode -format -force -nonInteractive >/dev/null 2>&1 || true
        start-dfs.sh >/dev/null 2>&1 || true
      fi
    ' 2>/dev/null || true
  fi
  # HDFS: retry up to ~60s, ensure safemode OFF and command works
  for i in {1..6}; do
    if docker exec "$container" bash -lc 'hdfs dfsadmin -safemode get 2>/dev/null | grep -q OFF && hdfs dfs -ls / >/dev/null 2>&1' 2>/dev/null; then
      HDFS_OK=true
      break
    fi
    sleep 10
  done
  if [ "$HDFS_OK" = true ]; then echo "  ✓ HDFS healthy"; else echo "  ✗ HDFS not ready"; fi

  # Spark: retry up to ~60s
  for i in {1..6}; do
    if docker exec "$container" bash -lc 'spark-submit --version >/dev/null 2>&1' 2>/dev/null; then
      SPARK_OK=true
      break
    fi
    sleep 10
  done
  if [ "$SPARK_OK" = true ]; then echo "  ✓ Spark healthy"; else echo "  ✗ Spark not ready"; fi

  # Hive: retry up to ~60s (6 attempts x 10s timeout each)
  for i in {1..6}; do
    if docker exec "$container" bash -lc 'timeout 10s hive -e "show databases;" >/dev/null 2>&1' 2>/dev/null; then
      HIVE_OK=true
      break
    fi
    sleep 10
  done
  if [ "$HIVE_OK" = true ]; then
    echo "  ✓ Hive healthy"
  else
    echo "  ✗ Hive not ready"
  fi
  echo "Health checks complete!"
  echo ""
  echo ""
  echo "=================================================="
  if [ "$HDFS_OK" = true ] && [ "$SPARK_OK" = true ] && [ "$HIVE_OK" = true ]; then
    echo "[+] Setup complete!"
  else
    echo "⚠ Some services are not fully ready yet"
    [ "$HDFS_OK" = true ] || echo "  ✗ HDFS not ready"
    [ "$SPARK_OK" = true ] || echo "  ✗ Spark not ready"
    [ "$HIVE_OK" = true ] || echo "  ✗ Hive not ready"
  fi
  echo "=================================================="
}

# -----------------------------------------------------------------------------
# Start services
# -----------------------------------------------------------------------------
echo ""
echo "=================================================="
echo "Starting services with images:"
echo "  Hive Metastore: $HIVE_METASTORE_IMAGE"
echo "  Spark Hadoop  : $SPARK_HADOOP_IMAGE"
echo ""
echo "Selected cluster type:"
echo "  Mode          : $MODE node cluster"
echo "=================================================="
COMPOSE_FILE="docker-compose.single.yml"
if [ "$MODE" = "multi" ]; then
  COMPOSE_FILE="docker-compose.yml"
fi
docker-compose -f "$COMPOSE_FILE" up -d

if [ "$MODE" = "single" ]; then
  # Initialize HDFS and Hive warehouse dirs
  docker exec -i spark bash -lc '
      hdfs namenode -format -force >/dev/null 2>&1 || true &&
      start-dfs.sh >/dev/null 2>&1 || true &&
    hdfs dfs -mkdir -p /tmp &&
    hdfs dfs -mkdir -p /user/hive/warehouse &&
    hdfs dfs -chmod g+w /user/hive/warehouse
  ' 2>/dev/null || true

  # Start Hive Metastore (background) then HiveServer2
  docker exec -d spark bash -lc '
    hive --service metastore &
    sleep 20
    hive --service hiveserver2
  ' 2>/dev/null || true

  # Basic health checks (HDFS, Spark, Hive)
  health_check spark
  echo ""
  echo "[+]Run the following command to connect to the Spark container:"
  echo "   docker exec -it spark bash"
  echo ""
  echo "[+] Run the following commands to start the following services:"
  echo "  - Spark Shell: spark-shell"
  echo "  - PySpark    : pyspark"
  echo "  - Hive       : hive"
  echo "  - Beeline    : beeline"
  echo "  - HDFS       : hdfs dfs -ls /"
  echo ""
  echo "[+]UIs:"
  echo "    - Spark UI        : http://localhost:4040"
  echo "    - Spark History   : http://localhost:8090"
  echo ""
  echo "=================================================="
else
  echo ""
  echo "=================================================="
  # Self-heal HDFS on multi-node if NameNode is not responding or has incompatible layout (no rebuild)
  docker exec -i spark-master bash -lc '
    set -e
    # If NN RPC or safemode query fails, attempt clean re-init (handles incompatible old layout)
    if ! hdfs dfsadmin -safemode get >/dev/null 2>&1; then
      export HDFS_NAMENODE_USER=root HDFS_DATANODE_USER=root HDFS_SECONDARYNAMENODE_USER=root
      (stop-dfs.sh || true) >/dev/null 2>&1 || true
      rm -rf /usr/bin/data/nameNode/* /usr/bin/data/nameNodeSecondary/* /usr/bin/data/dataNode/* || true
      hdfs namenode -format -force -nonInteractive >/dev/null 2>&1 || true
      start-dfs.sh >/dev/null 2>&1 || true
    fi
    # Wait for RPC port and safemode OFF (max ~120s)
    for i in {1..120}; do (echo > /dev/tcp/hadoop.spark/9000) >/dev/null 2>&1 && break; sleep 1; done
    for i in {1..120}; do hdfs dfsadmin -safemode get 2>/dev/null | grep -q OFF && break; sleep 1; done
    # Ensure Hive dirs exist
    hdfs dfs -mkdir -p /tmp /user/hive/warehouse || true
    hdfs dfs -chmod 1777 /tmp || true
    hdfs dfs -chmod g+w /user/hive/warehouse || true
  ' 2>/dev/null || true

  # Basic health checks for multi-node (run against spark-master)
  health_check spark-master
  echo ""
  echo "[+] Connect to the Spark master container:"
  echo "    docker exec -it spark-master bash"
  echo ""
  echo "[+] Run the following commands to start the following services:"
  echo "  - Spark Shell: spark-shell --master spark://hadoop.spark:7077"
  echo "  - PySpark    : pyspark --master spark://hadoop.spark:7077"
  echo "  - Hive CLI   : hive"
  echo "  - Beeline    : beeline"
  echo "  - HDFS       : hdfs dfs -ls /"
  echo ""
  echo "[+] UIs:"
  echo "  - Spark UI        : http://localhost:4040"
  echo "  - Spark Master UI : http://localhost:8080"
  echo "  - Spark History   : http://localhost:8090"
  echo "  - HDFS NameNode   : http://localhost:50070"
  echo ""
  echo "=================================================="
fi
