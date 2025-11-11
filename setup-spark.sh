#!/usr/bin/env bash

# =============================================================================
# Spark with Hadoop Setup Script
# =============================================================================
# Description: Sets up Spark 3.5.7 with Hadoop 3.3.6 and Hive 4.0.0
# Requirements: Docker, Docker Compose
# 
# Usage:
#   ./setup-spark.sh --run              # Pull images from DockerHub
#   ./setup-spark.sh --build --run      # Build images locally
#
# Components:
#   - Java 17 (Adoptium Temurin)
#   - Spark 3.5.7 (Scala 2.13)
#   - Hadoop 3.3.6
#   - Hive 4.0.0
#   - PostgreSQL metastore
# =============================================================================

set -eo pipefail

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Wait for a condition with timeout
wait_for_condition() {
  local description=$1
  local command=$2
  local timeout=$3
  local interval=${4:-3}
  
  echo "Waiting for $description..."
  local elapsed=0
  
  while [ $elapsed -lt $timeout ]; do
    if eval "$command" 2>/dev/null; then
      echo "✓ $description ready"
      return 0
    fi
    
    if [ $((elapsed % 15)) -eq 0 ] && [ $elapsed -gt 0 ]; then
      echo "  Still waiting... (${elapsed}s/${timeout}s)"
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  
  echo "⚠ Warning: $description not ready within ${timeout}s"
  return 1
}

# Print section header
print_section() {
  echo ""
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------

BUILD_MODE=false
RUN_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --build) BUILD_MODE=true; shift ;;
    --run) RUN_MODE=true; shift ;;
    *)
      echo "Error: Unknown option '$1'"
      echo ""
      echo "Usage: $0 [--build] [--run]"
      echo "  --run         : Pull images from DockerHub (fast)"
      echo "  --build --run : Build images locally (slow, for development)"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ "$RUN_MODE" = false ]; then
  echo "Error: Please specify --run"
  echo "Usage: $0 [--build] --run"
  exit 1
fi

if [ "$BUILD_MODE" = true ] && [ "$RUN_MODE" = false ]; then
  echo "Error: --build requires --run"
  exit 1
fi

# -----------------------------------------------------------------------------
# Step 1: Build or Pull Docker Images
# -----------------------------------------------------------------------------

if [ "$BUILD_MODE" = true ]; then
  print_section "Building Docker images locally (this takes 10-15 minutes)"
  
  docker build -t hive-metastore:local -f hive-metastore/Dockerfile .
  docker build -t spark-with-hadoop:local -f spark-hadoop-standalone/Dockerfile .
  
  export HIVE_METASTORE_IMAGE="hive-metastore:local"
  export SPARK_HADOOP_IMAGE="spark-with-hadoop:local"
else
  print_section "Pulling images from DockerHub"
  
  docker pull docker4ops/hive-metastore:hive-4.0.0
  docker pull docker4ops/spark-with-hadoop:spark-3.5.7_hadoop-3.3.6_hive-4.0.0
  
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-4.0.0"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-3.5.7_hadoop-3.3.6_hive-4.0.0"
fi

# -----------------------------------------------------------------------------
# Step 2: Start Containers
# -----------------------------------------------------------------------------

print_section "Starting containers"
docker-compose up -d

# Wait for containers to be running
wait_for_condition "containers" \
  "docker inspect -f '{{.State.Status}}' spark 2>/dev/null | grep -q running && \
   docker inspect -f '{{.State.Status}}' hive_metastore 2>/dev/null | grep -q running" \
  30 2

# -----------------------------------------------------------------------------
# Step 3: Initialize HDFS
# -----------------------------------------------------------------------------

print_section "Initializing HDFS"
docker exec spark bash -lc '
  hdfs namenode -format -force &&
  start-dfs.sh &&
  sleep 5 &&
  hdfs dfs -mkdir -p /tmp &&
  hdfs dfs -mkdir -p /user/hive/warehouse &&
  hdfs dfs -chmod g+w /user/hive/warehouse
' 2>&1 | grep -v -e "warning: setlocale" -e "namenode is running" -e "Stop it first" -e ".pid file is empty" || true

# -----------------------------------------------------------------------------
# Step 4: Initialize Hive Metastore Schema
# -----------------------------------------------------------------------------

echo ""
echo "Checking Hive metastore schema..."

# Check if schema already exists
SCHEMA_INFO=$(docker exec spark bash -lc 'schematool -dbType postgres -info 2>&1' || true)

if echo "$SCHEMA_INFO" | grep -q "Metastore schema version:.*4.0.0"; then
  echo "✓ Hive schema already exists (version 4.0.0)"
else
  echo "Initializing Hive schema (this takes ~30 seconds)..."
  docker exec spark bash -lc 'schematool -dbType postgres -initSchema' 2>&1 | \
    grep -E "Initialization script|completed|SUCCESS" || echo "Note: Schema may already exist"
fi

# -----------------------------------------------------------------------------
# Step 5: Start Hive Services
# -----------------------------------------------------------------------------

print_section "Starting Hive Metastore and HiveServer2"

# Start both services in background
docker exec -d spark bash -lc '
  hive --service metastore &
  sleep 15
  hive --service hiveserver2
' 2>&1 | grep -v "warning: setlocale" || true

# Wait for HiveServer2 to be ready (port 10000)
# Note: Hive 4.0.0 takes 2-3 minutes to fully initialize
echo ""
echo "Waiting for HiveServer2 to start (this takes 2-3 minutes)..."

wait_for_condition "HiveServer2" \
  "docker exec spark bash -c 'netstat -tulpn 2>/dev/null | grep -q \":10000 \"'" \
  180 3

# -----------------------------------------------------------------------------
# Validate All Services Before Completion
# -----------------------------------------------------------------------------

echo ""
echo "Running final health checks..."

# Initialize error tracking
ERRORS=()

# Test 1: HDFS
echo "  Testing HDFS..."
HDFS_ERROR=$(docker exec spark bash -c 'hdfs dfs -ls / 2>&1' | grep -i "error\|exception" | head -1)
if docker exec spark bash -c 'hdfs dfs -ls / >/dev/null 2>&1'; then
  echo "    ✓ HDFS is working"
else
  echo "    ✗ HDFS test failed"
  if [ -n "$HDFS_ERROR" ]; then
    ERRORS+=("HDFS: $HDFS_ERROR")
  else
    ERRORS+=("HDFS: Cannot list root directory")
  fi
fi

# Test 2: Spark
echo "  Testing Spark..."
SPARK_VERSION=$(docker exec spark bash -c 'spark-shell --version 2>&1 | grep "version" | head -1' || echo "")
if docker exec spark bash -c 'spark-shell --version 2>&1 | grep -q "version 3.5.7"'; then
  echo "    ✓ Spark is working"
else
  echo "    ✗ Spark test failed"
  if [ -n "$SPARK_VERSION" ]; then
    ERRORS+=("Spark: Expected version 3.5.7, found: $SPARK_VERSION")
  else
    ERRORS+=("Spark: Version check failed - spark-shell not responding")
  fi
fi

# Test 3: Hive Metastore
echo "  Testing Hive Metastore..."
if docker exec spark bash -c 'netstat -tulpn 2>/dev/null | grep -q ":9083"'; then
  echo "    ✓ Hive Metastore is working"
else
  echo "    ✗ Hive Metastore not running"
  METASTORE_PROCESS=$(docker exec spark bash -c 'ps aux | grep "metastore.HiveMetaStore" | grep -v grep' || echo "")
  if [ -n "$METASTORE_PROCESS" ]; then
    ERRORS+=("Hive Metastore: Process running but port 9083 not listening (still initializing?)")
  else
    ERRORS+=("Hive Metastore: Process not running - check logs with: docker exec spark tail -50 /tmp/root/hive.log")
  fi
fi

# Test 4: HiveServer2
echo "  Testing HiveServer2..."
if docker exec spark bash -c 'netstat -tulpn 2>/dev/null | grep -q ":10000"'; then
  echo "    ✓ HiveServer2 is working"
else
  echo "    ✗ HiveServer2 not running"
  HIVESERVER_PROCESS=$(docker exec spark bash -c 'ps aux | grep "HiveServer2" | grep -v grep' || echo "")
  if [ -n "$HIVESERVER_PROCESS" ]; then
    ERRORS+=("HiveServer2: Process running but port 10000 not listening (still initializing?)")
  else
    ERRORS+=("HiveServer2: Process not running - check logs with: docker exec spark tail -50 /tmp/root/hive.log")
  fi
fi

# -----------------------------------------------------------------------------
# Show Results
# -----------------------------------------------------------------------------

if [ ${#ERRORS[@]} -eq 0 ]; then
  # All tests passed - show success message
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
else
  # Some tests failed - show error message
  echo ""
  echo "============================================================"
  echo "⚠ Setup incomplete - Some services failed health checks"
  echo "============================================================"
  echo ""
  echo "Failed services:"
  for error in "${ERRORS[@]}"; do
    echo "  ✗ $error"
  done
  echo ""
  echo "Troubleshooting:"
  echo "  1. Check all services:"
  echo "     docker exec spark ps aux | grep -E 'java|hdfs'"
  echo ""
  echo "  2. Check logs:"
  echo "     docker logs spark"
  echo "     docker exec spark tail -50 /tmp/root/hive.log"
  echo ""
  echo "  3. Restart services:"
  echo "     docker-compose restart"
  echo ""
  echo "============================================================"
  exit 1
fi
