#!/usr/bin/env bash

# =============================================================================
# Spark with Hadoop Setup Script
# =============================================================================
# Description: Sets up Spark 3.5.0 with Hadoop 3.3.6 and Hive 3.1.3
# Requirements: Docker, Docker Compose
#
# Usage:
#   sh setup-spark.sh [OPTIONS]
#
#   Required:
#     --run                       Pull images from Docker Hub and run
#     --build --run               Build images locally and run
#
#   Optional:
#     --node-type {single|multi}  Single or multi-node cluster (default: single)
#     --stop                      Stop & clean up containers and images
#     --help                      Show this help message
#
# Components:
#   - Java 8 
#   - Spark 3.5.0 (Scala 2.12)
#   - Hadoop 3.3.6
#   - Hive 3.1.3
#   - PostgreSQL metastore
# =============================================================================

set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script requires bash. Run: bash $0 [--build] [--run] [--node-type single|multi]"
  exit 1
fi

# -----------------------------------------------------------------------------
# Helper output functions
# -----------------------------------------------------------------------------

# ANSI colors (disable if not a TTY)
RESET="\033[0m"
GREEN="\033[32m"
if [ ! -t 1 ]; then
  RESET=""
  GREEN=""
fi

info() {
  # Colored INFO: [+] prefix for key steps
  printf "%bINFO: [+]%b %s\n" "$GREEN" "$RESET" "$*"
}

print_section() {
  echo ""
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

show_help() {
  cat <<EOF
Usage: $0 [--build] [--run] [--stop] [--node-type single|multi] [--help]

Required:
  --run                 Pull images from Docker Hub and run (preferred)
  --build --run         Build images locally and run

Optional:
  --node-type single    Single container / single node cluster (default)
  --node-type multi     Spark master + workers / multi node cluster
  --stop                Stop and remove the selected stack (and images)
  --help                Show this help message

Examples:
  $0 --run
  $0 --build --run
  $0 --run --node-type multi
  $0 --stop
EOF
}

# -----------------------------------------------------------------------------
# Parse command line arguments
# -----------------------------------------------------------------------------

BUILD_MODE=false
RUN_MODE=false
STOP_MODE=false
MODE="single" # single | multi
HELP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      HELP=true
      shift
      ;;
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
      echo ""
      show_help
      exit 1
      ;;
  esac
done

if [ "$HELP" = true ]; then
  show_help
  exit 0
fi

# -----------------------------------------------------------------------------
# Validate node-type
# -----------------------------------------------------------------------------

if [ "$MODE" != "single" ] && [ "$MODE" != "multi" ]; then
  echo "Error: Invalid --node-type value: '$MODE'"
  echo "Allowed values: single, multi"
  echo ""
  show_help
  exit 1
fi

# -----------------------------------------------------------------------------
# Validate other arguments
# -----------------------------------------------------------------------------

if [ "$BUILD_MODE" = false ] && [ "$RUN_MODE" = false ] && [ "$STOP_MODE" = false ]; then
  echo "Error: Please specify --run or --build --run or --stop"
  echo ""
  show_help
  exit 1
fi

if [ "$BUILD_MODE" = true ] && [ "$RUN_MODE" = false ]; then
  echo "Error: --build must be used with --run"
  echo ""
  echo "Example: $0 --build --run"
  exit 1
fi

# -----------------------------------------------------------------------------
# Stop the services: select compose file and bring the stack down
# -----------------------------------------------------------------------------

if [ "$STOP_MODE" = true ]; then
  print_section "Stopping services (auto-detected)"

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
  docker rmi -f $(docker images -a -q) >/dev/null 2>&1 || true

  echo "Pruning Docker system (networks, caches, etc.)..."
  docker system prune -f >/dev/null 2>&1 || true
  docker volume prune -f >/dev/null 2>&1 || true

  echo "Done."
  exit 0
fi

# -----------------------------------------------------------------------------
# Build or Pull images
# -----------------------------------------------------------------------------

if [ "$BUILD_MODE" = true ]; then
  echo ""
  echo "**** This setup may take around 10–15 minutes... grab a coffee or tea and relax! ****"
  print_section "Building images locally"

  docker build -t hive-metastore:local \
    -f hive-metastore/Dockerfile .
  
  docker build -t spark-with-hadoop:local \
    -f spark-hadoop-standalone/Dockerfile .
  
  echo "Build complete!"

  export HIVE_METASTORE_IMAGE="hive-metastore:local"
  export SPARK_HADOOP_IMAGE="spark-with-hadoop:local"
else
  echo ""
  echo "**** This setup may take around 5–7 minutes... grab a coffee or tea and relax! ****"
  print_section "Pulling images from Docker Hub"

  docker pull docker4ops/hive-metastore:hive-3.1.3
  docker pull docker4ops/spark-with-hadoop:spark-3.5.0_hadoop-3.3.6_hive-3.1.3

  echo "Pull complete!"
  
  # Set environment variables to use Docker Hub images (default)
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-3.1.3"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-3.5.0_hadoop-3.3.6_hive-3.1.3"
fi

# -----------------------------------------------------------------------------
# HDFS Self-Heal Function
# -----------------------------------------------------------------------------
fix_hdfs() {
  local container=$1
  echo ""
  echo "=================================================="
  info "Attempting to fix HDFS..."
  echo "=================================================="
  
  # Stop HDFS services
  echo "→ Stopping HDFS services..."
  docker exec "$container" bash -c 'stop-dfs.sh' >/dev/null 2>&1 || true
  sleep 3
  
  # Clean corrupt HDFS data
  echo "→ Cleaning HDFS data directories..."
  docker exec "$container" bash -c '
    rm -rf /usr/bin/data/nameNode/* \
           /usr/bin/data/dataNode/* \
           /usr/bin/data/nameNodeSecondary/* 2>/dev/null || true
  ' >/dev/null 2>&1
  
  # Reformat NameNode
  echo "→ Reformatting HDFS NameNode..."
  if docker exec "$container" bash -c 'hdfs namenode -format -force' 2>&1 | grep -q "successfully formatted"; then
    echo "  ✓ NameNode format successful"
    
    # Verify fsimage file was created
    if docker exec "$container" bash -c '[ -f /usr/bin/data/nameNode/current/fsimage_0000000000000000000 ]' 2>/dev/null; then
      echo "  ✓ Verified: fsimage file created"
    else
      echo "  ✗ Warning: fsimage file not found"
    fi
  else
    echo "  ✗ NameNode format may have failed"
  fi
  
  # Restart HDFS services
  echo "→ Restarting HDFS services..."
  docker exec "$container" bash -c 'start-dfs.sh' >/dev/null 2>&1 &
  
  # Wait for NameNode to start
  echo "→ Waiting for NameNode to be ready..."
  local waited=0
  local max_wait=45
  while [ $waited -lt $max_wait ]; do
    if docker exec "$container" bash -c 'timeout 5 hdfs dfs -ls / >/dev/null 2>&1' 2>/dev/null; then
      echo "  ✓ HDFS is now responding"
      echo "=================================================="
      return 0
    fi
    if [ $((waited % 10)) -eq 0 ] && [ $waited -gt 0 ]; then
      echo "  Still waiting... (${waited}s/${max_wait}s)"
    fi
    sleep 3
    waited=$((waited + 3))
  done
  
  echo "  ✗ HDFS did not recover after $max_wait seconds"
  echo "=================================================="
  return 1
}

# -----------------------------------------------------------------------------
# Health check helper
# -----------------------------------------------------------------------------

health_check() {
  local container="$1"
  echo ""
  info "Waiting 10 seconds for containers to completely start before health checks..."
  sleep 10

  info "Starting health checks for all services"
  local HDFS_OK=false
  local SPARK_OK=false
  local HIVE_OK=false

  echo "        Testing HDFS..."
  for _ in {1..6}; do
    if docker exec "$container" bash -lc 'timeout 10s hdfs dfs -ls / >/dev/null 2>&1' 2>/dev/null; then
      HDFS_OK=true
      echo "        ✓ HDFS ready"
      break
    else
      echo "       Waiting for HDFS to be ready..."
      sleep 10
    fi
  done
  
  # If HDFS failed initial checks, attempt automatic fix
  if [ "$HDFS_OK" = false ]; then
    echo "        ✗ HDFS not ready - attempting automatic fix..."
    if fix_hdfs "$container"; then
      HDFS_OK=true
      echo "        ✓ HDFS recovered successfully"
    else
      echo "        ✗ HDFS auto-fix failed"
    fi
  fi

  echo "        Testing Spark..."
  for _ in {1..6}; do
    if docker exec "$container" bash -lc 'timeout 10s spark-submit --version >/dev/null 2>&1' 2>/dev/null; then
      SPARK_OK=true
      echo "        ✓ Spark ready"
      break
    else
      echo "       Waiting for Spark to be ready..."
      sleep 10
    fi
  done
  if [ "$SPARK_OK" = false ]; then
    echo "        ✗ Spark not ready"
  fi

  echo "        Testing Hive..."
  for _ in {1..6}; do
    if docker exec "$container" bash -lc 'timeout 20s hive -e "show databases;" >/dev/null 2>&1' 2>/dev/null; then
      HIVE_OK=true
      echo "        ✓ Hive ready"
      break
    else
      echo "        Waiting for Hive to be ready..."
      sleep 10
    fi
  done
  if [ "$HIVE_OK" = false ]; then
    echo "        ✗ Hive not ready"
  fi

  info "Health checks complete!"
  echo ""
  echo "=================================================="
  if [ "$HDFS_OK" = true ] && [ "$SPARK_OK" = true ] && [ "$HIVE_OK" = true ]; then
    info "Setup complete!"
  else
    echo "⚠ Some services are not fully ready yet. Please wait a few minutes stop and start again."
    exit 1
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
  docker exec -i spark bash -lc '
    hdfs namenode -format -force &&
    start-dfs.sh &&
    hdfs dfs -mkdir -p /tmp &&
    hdfs dfs -mkdir -p /user/hive/warehouse &&
    hdfs dfs -chmod g+w /user/hive/warehouse
  ' 2>/dev/null || true

  docker exec -d spark bash -lc '
    hive --service metastore &
    sleep 20
    hive --service hiveserver2
  ' 2>/dev/null || true

  health_check spark

  echo ""
  info "Run the following command to connect to the Spark container:"
  echo "          docker exec -it spark bash"
  echo ""
  info "Useful commands to run inside the container:"
  echo "        - Spark Shell : spark-shell"
  echo "        - PySpark     : pyspark"
  echo "        - Hive        : hive"
  echo "        - Beeline     : beeline"
  echo "        - HDFS        : hdfs dfs -ls /"
  echo ""
  info "UIs:"
  echo "        - Spark UI        : http://localhost:4040"
  echo "        - Spark History   : http://localhost:8090"
  echo ""
  echo "=================================================="
else
  health_check spark-master

  echo ""
  info "Run the following command to connect to the Spark container:"
  echo "          docker exec -it spark-master bash"
  echo ""
  info "Useful commands to run inside the container:"
  echo "        - Spark Shell : spark-shell --master spark://hadoop.spark:7077"
  echo "        - PySpark     : pyspark --master spark://hadoop.spark:7077"
  echo "        - Hive CLI    : hive"
  echo "        - Beeline     : beeline"
  echo "        - HDFS        : hdfs dfs -ls /"
  echo ""
  info "UIs:"
  echo "       - Spark UI        : http://localhost:4040"
  echo "       - Spark Master UI : http://localhost:8080"
  echo "       - Spark History   : http://localhost:8090"
  echo "       - HDFS NameNode   : http://localhost:50070"
  echo ""
  echo "=================================================="
fi
