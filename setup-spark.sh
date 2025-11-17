#!/usr/bin/env bash

# =============================================================================
# Spark with Hadoop Setup Script (Generic: single & multi node)
# =============================================================================
# Description: Sets up Spark 3.5.2 with Hadoop 3.3.6 and Hive 4.0.0 on Scala 2.13
# Requirements: Docker, Docker Compose
# 
# Usage:
#   ./setup-spark.sh --run                                # Pull images from DockerHub
#   ./setup-spark.sh --build --run                        # Build images locally
#   ./setup-spark.sh --run --node-type {multi|single}     # Multi-node cluster
#   ./setup-spark.sh --stop                               # Stop & cleanup
#
# Components:
#   - Java 17 (Adoptium Temurin)
#   - Spark 3.5.2 (Scala 2.13)
#   - Hadoop 3.3.6
#   - Hive 4.0.0
#   - PostgreSQL metastore
# =============================================================================

set -euo pipefail

# Ensure we are running under bash even if invoked via `sh`
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Wait for a condition with timeout
wait_for_condition() {
  local description=$1
  local command=$2
  local timeout=$3
  local interval=${4:-3}
  
  info "Waiting for $description"
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
# Colored output helpers
# -----------------------------------------------------------------------------
# ANSI colors (disable if not a TTY)
RESET="\033[0m"; GREEN="\033[32m"
if [ ! -t 1 ]; then RESET=""; GREEN=""; fi

info() {
  # Print a colored "INFO: [+]" prefix followed by the message
  printf "%bINFO: [+]%b %s\n" "$GREEN" "$RESET" "$*"
}

# -----------------------------------------------------------------------------
# CLI Argument Parsing
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
      echo "  --run                 : Pull images from Docker Hub and run (preferred)"
      echo "  --build --run         : Build images locally and run"
      echo "  --stop                : Stop and remove the selected stack"
      echo " Optional arguments:"
      echo "  --node-type single    : Single container/Single node cluster (default)"
      echo "  --node-type multi     : Spark master + workers cluster/Multi node cluster"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ "$BUILD_MODE" = false ] && [ "$RUN_MODE" = false ] && [ "$STOP_MODE" = false ]; then
  echo "Error: Please specify --run or --build --run or --stop"
  echo "Usage: $0 [--build] [--run] [--stop] [--node-type single|multi]"
  exit 1
fi

if [ "$BUILD_MODE" = true ] && [ "$RUN_MODE" = false ]; then
  echo "Error: --build must be used with --run"
  echo "Usage: $0 --build --run"
  exit 1
fi

# Strict validation of node-type (catch things like --node-type=aaaa)
if [ "$MODE" != "single" ] && [ "$MODE" != "multi" ]; then
  echo "Error: Invalid --node-type '$MODE'. Allowed values: single|multi"
  exit 1
fi

# -----------------------------------------------------------------------------
# Early stop: select compose file and bring the stack down
# -----------------------------------------------------------------------------
if [ "$STOP_MODE" = true ]; then
  print_section "Stopping services (auto-detected)"
  # Auto-detect running stack by container names
  if docker ps --format '{{.Names}}' | grep -q '^spark$'; then
    info "[single] Detected 'spark' container. Bringing down docker-compose.single.yml..."
    docker-compose -f "docker-compose.single.yml" down
  elif docker ps --format '{{.Names}}' | grep -q '^spark-master$'; then
    info "[multi] Detected 'spark-master' container. Bringing down docker-compose.yml..."
    docker-compose -f "docker-compose.yml" down
  else
    info "No known containers running (spark or spark-master). Attempting best-effort stop on both stacks..."
    docker-compose -f "docker-compose.single.yml" down || true
    docker-compose -f "docker-compose.yml" down || true
  fi
  echo ""
  echo "Removing all Docker images (this may take a while)..."
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
  print_section "Building images locally"
  
  docker build -t hive-metastore:local \
    -f hive-metastore/Dockerfile .
  
  docker build -t spark-with-hadoop:local \
    -f spark-hadoop-standalone/Dockerfile .
  
  echo "Build complete!"
  
  export HIVE_METASTORE_IMAGE="hive-metastore:local"
  export SPARK_HADOOP_IMAGE="spark-with-hadoop:local"
else
  print_section "Pulling images from Docker Hub"
  
  docker pull docker4ops/hive-metastore:hive-4.0.0
  docker pull docker4ops/spark-with-hadoop:spark-3.5.2_hadoop-3.3.6_hive-4.0.0_scala-2.13

  echo "Pull complete!"
  
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-4.0.0"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-3.5.2_hadoop-3.3.6_hive-4.0.0_scala-2.13"
fi

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
PRIMARY_CONTAINER="spark"

if [ "$MODE" = "multi" ]; then
  COMPOSE_FILE="docker-compose.yml"
  PRIMARY_CONTAINER="spark-master"
fi

docker-compose -f "$COMPOSE_FILE" up -d

METASTORE_DB_CONTAINER="hive_metastore"
SPARK_VERSION_EXPECTED="3.5.2"

# -----------------------------------------------------------------------------
# Common initialization for BOTH single & multi node
# -----------------------------------------------------------------------------

# Wait for primary + DB containers
wait_for_condition "containers ($PRIMARY_CONTAINER, $METASTORE_DB_CONTAINER)" \
  "docker inspect -f '{{.State.Status}}' $PRIMARY_CONTAINER 2>/dev/null | grep -q running && \
   docker inspect -f '{{.State.Status}}' $METASTORE_DB_CONTAINER 2>/dev/null | grep -q running" \
  60 2

# Step 1: Initialize HDFS (format + start-dfs)
echo ""
info "Initializing HDFS on $PRIMARY_CONTAINER"
docker exec "$PRIMARY_CONTAINER" bash -c '
  hdfs namenode -format -force &&
  HDFS_NAMENODE_USER=root HDFS_DATANODE_USER=root HDFS_SECONDARYNAMENODE_USER=root start-dfs.sh &&
  sleep 5 &&
  hdfs dfs -mkdir -p /tmp &&
  hdfs dfs -mkdir -p /user/hive/warehouse &&
  hdfs dfs -chmod g+w /user/hive/warehouse
' >/dev/null 2>&1 || true
echo "✓ HDFS initialization completed on $PRIMARY_CONTAINER"

# Step 2: Initialize Hive Metastore Schema (Postgres)
echo ""
info "Waiting for Hive Metastore PostgreSQL ($METASTORE_DB_CONTAINER) to be ready..."

for _ in $(seq 1 20); do
  if docker exec "$METASTORE_DB_CONTAINER" pg_isready -U hive -d metastore >/dev/null 2>&1; then
    echo "PostgreSQL responding, waiting for full initialization..."
    sleep 15
    echo "✓ PostgreSQL ready"
    break
  fi
  sleep 2
done

echo ""
info "Checking Hive metastore schema"

SCHEMA_CHECK=$(docker exec "$PRIMARY_CONTAINER" bash -c 'schematool -dbType postgres -info 2>&1 | grep "Metastore schema version"' || echo "")

if [ -n "$SCHEMA_CHECK" ]; then
  echo "✓ Hive schema already exists"
else
  echo "Initializing Hive schema (this takes ~20 seconds)..."
  docker exec "$PRIMARY_CONTAINER" bash -c 'schematool -dbType postgres -initSchema' >/dev/null 2>&1
  
  sleep 2
  SCHEMA_CHECK=$(docker exec "$PRIMARY_CONTAINER" bash -c 'schematool -dbType postgres -info 2>&1 | grep "Metastore schema version"' || echo "")
  if [ -n "$SCHEMA_CHECK" ]; then
    echo "✓ Schema initialized successfully"
  else
    echo "⚠ Schema initialization failed, retrying once..."
    docker exec "$PRIMARY_CONTAINER" bash -c 'schematool -dbType postgres -initSchema' >/dev/null 2>&1
    sleep 2
    SCHEMA_CHECK=$(docker exec "$PRIMARY_CONTAINER" bash -c 'schematool -dbType postgres -info 2>&1 | grep "Metastore schema version"' || echo "")
    if [ -n "$SCHEMA_CHECK" ]; then
      echo "✓ Schema initialized successfully on retry"
    else
      echo "✗ Schema initialization failed - Hive may not work properly"
    fi
  fi
fi

# Step 3: Start Hive Metastore + HiveServer2 in PRIMARY_CONTAINER
echo ""
info "Starting Hive Metastore and HiveServer2 on $PRIMARY_CONTAINER"

set +e

docker exec "$PRIMARY_CONTAINER" bash -c 'pkill -9 -f "HiveMetaStore|HiveServer2" 2>/dev/null || true'
sleep 1

echo "Starting Hive Metastore"
docker exec "$PRIMARY_CONTAINER" bash -c 'nohup hive --service metastore >/tmp/root/metastore.log 2>&1 & echo $! > /tmp/root/metastore.pid && disown' >/dev/null 2>&1 || true

echo "Waiting for Metastore to start"
METASTORE_READY=false
META_START_TS=$(date +%s)
for i in $(seq 1 90); do
  if docker exec "$PRIMARY_CONTAINER" bash -c 'ss -tulpn 2>/dev/null | grep -q 9083 || grep -q "Starting Hive Metastore Server" /tmp/root/metastore.log 2>/dev/null'; then
    METASTORE_READY=true; echo "✓ Metastore ready"; break
  fi
  NOW=$(date +%s); ELAPSED=$((NOW - META_START_TS))
  if (( i % 10 == 0 )); then echo "  Still waiting for Metastore... (${ELAPSED}s elapsed)"; fi
  sleep 2
done
if [ "$METASTORE_READY" != true ]; then
  echo "✗ Metastore did not start in time. Last log lines:"; docker exec "$PRIMARY_CONTAINER" bash -c 'tail -80 /tmp/root/metastore.log || true'
  exit 1
fi

echo "Starting HiveServer2"
docker exec "$PRIMARY_CONTAINER" bash -c 'nohup hive --service hiveserver2 >/tmp/root/hiveserver2.log 2>&1 & echo $! > /tmp/root/hiveserver2.pid && disown' >/dev/null 2>&1 || true

echo "Waiting for HiveServer2 to start (this may take up to 3 minutes)"
HS2_READY=false
HS2_START_TS=$(date +%s)
HS2_PORT_SEEN=false
MAX_WAIT_SEC=600
while :; do
  if docker exec "$PRIMARY_CONTAINER" bash -c 'ss -tulpn 2>/dev/null | grep -q 10000 || grep -q "Starting ThriftBinaryCLIService on port" /tmp/root/hive*.log 2>/dev/null || grep -q "Service:HiveServer2 is started" /tmp/root/hive*.log 2>/dev/null'; then
    HS2_PORT_SEEN=true
  fi
  NOW=$(date +%s); ELAPSED=$((NOW - HS2_START_TS))
  if [ "$HS2_PORT_SEEN" = true ] && [ $ELAPSED -ge 180 ]; then
    HS2_READY=true; echo "✓ HiveServer2 ready"; break
  fi
  if [ $ELAPSED -ge $MAX_WAIT_SEC ]; then
    break
  fi
  if (( (ELAPSED % 10) == 0 )); then echo "  Still waiting... (${ELAPSED}s elapsed)"; fi
  sleep 2
done
if [ "$HS2_READY" != true ]; then
  echo "✗ HiveServer2 did not start in time. Last log lines:"; docker exec "$PRIMARY_CONTAINER" bash -c 'tail -80 /tmp/root/hiveserver2.log || true'
  exit 1
fi

echo "Waiting for HiveServer2 JDBC to become responsive..."
JDBC_READY=false
JDBC_START_TS=$(date +%s)
for i in $(seq 1 180); do
  if docker exec "$PRIMARY_CONTAINER" bash -c 'beeline -u jdbc:hive2://localhost:10000 -e "show databases;" >/dev/null 2>&1'; then
    JDBC_READY=true; echo "✓ HiveServer2 JDBC ready"; break
  fi
  NOW=$(date +%s); ELAPSED=$((NOW - JDBC_START_TS))
  if (( i % 10 == 0 )); then echo "  Still waiting for JDBC... (${ELAPSED}s elapsed)"; fi
  sleep 2
done
if [ "$JDBC_READY" != true ]; then
  echo "✗ HiveServer2 JDBC not responsive in time. Last HS2 log lines:"; docker exec "$PRIMARY_CONTAINER" bash -c 'tail -80 /tmp/root/hiveserver2.log || true'
  exit 1
fi

set -e

# -----------------------------------------------------------------------------
# Final rich health checks (generic for single & multi)
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
info "Running final health checks on $PRIMARY_CONTAINER"

ERRORS=()

echo "  Testing HDFS..."
if docker exec "$PRIMARY_CONTAINER" bash -c 'ps aux | grep -q "org.apache.hadoop.hdfs.server.namenode.NameNode" && ps aux | grep -q "org.apache.hadoop.hdfs.server.datanode.DataNode"'; then
  echo "    ✓ HDFS daemons are running"
else
  echo "    ⚠ HDFS daemons not detected, performing quick dfs check..."
  HDFS_ERROR=$(docker exec "$PRIMARY_CONTAINER" bash -c 'timeout 15s hdfs dfs -ls / 2>&1' | grep -i "error\|exception\|timed out" | head -1)
  if docker exec "$PRIMARY_CONTAINER" bash -c 'timeout 15s hdfs dfs -ls / >/dev/null 2>&1'; then
    echo "    ✓ HDFS is working"
  else
    echo "    ✗ HDFS test failed"
    if [ -n "$HDFS_ERROR" ]; then
      ERRORS+=("HDFS: $HDFS_ERROR")
    else
      ERRORS+=("HDFS: dfs check failed (timeout or unknown error)")
    fi
  fi
fi

echo "  Testing Spark..."
SPARK_VERSION=$(docker exec "$PRIMARY_CONTAINER" bash -c 'timeout 20s spark-submit --version 2>&1 | grep -E "version" | head -1' || echo "")
if docker exec "$PRIMARY_CONTAINER" bash -c "timeout 20s spark-submit --version 2>&1 | grep -q 'version $SPARK_VERSION_EXPECTED'"; then
  echo "    ✓ Spark is working"
else
  echo "    ✗ Spark test failed"
  if [ -n "$SPARK_VERSION" ]; then
    ERRORS+=("Spark: Expected version $SPARK_VERSION_EXPECTED, found: $SPARK_VERSION")
  else
    ERRORS+=("Spark: Version check failed - spark-submit not responding within timeout")
  fi
fi

echo "  Testing Hive Metastore..."
if docker exec "$PRIMARY_CONTAINER" bash -c 'ss -tulpn 2>/dev/null | grep -q ":9083"'; then
  echo "    ✓ Hive Metastore is working"
else
  echo "    ✗ Hive Metastore not running"
  METASTORE_PROCESS=$(docker exec "$PRIMARY_CONTAINER" bash -c 'ps aux | grep "metastore.HiveMetaStore" | grep -v grep' || echo "")
  if [ -n "$METASTORE_PROCESS" ]; then
    ERRORS+=("Hive Metastore: Process running but port 9083 not listening (still initializing?)")
  else
    ERRORS+=("Hive Metastore: Process not running - check logs: docker exec $PRIMARY_CONTAINER tail -50 /tmp/root/metastore.log")
  fi
fi

echo "  Testing HiveServer2..."
if docker exec "$PRIMARY_CONTAINER" bash -c 'ss -tulpn 2>/dev/null | grep -q ":10000"'; then
  echo "    ✓ HiveServer2 is working"
else
  echo "    ✗ HiveServer2 not running"
  HIVESERVER_PROCESS=$(docker exec "$PRIMARY_CONTAINER" bash -c 'ps aux | grep "HiveServer2" | grep -v grep' || echo "")
  if [ -n "$HIVESERVER_PROCESS" ]; then
    ERRORS+=("HiveServer2: Process running but port 10000 not listening (still initializing?)")
  else
    ERRORS+=("HiveServer2: Process not running - check logs: docker exec $PRIMARY_CONTAINER tail -50 /tmp/root/hiveserver2.log")
  fi
fi

# -----------------------------------------------------------------------------
# Show Results
# -----------------------------------------------------------------------------

if [ ${#ERRORS[@]} -eq 0 ]; then

  info "All services are Healthy"
  echo "============================================================"
  echo "Spark with Hadoop setup completed successfully !"
  echo "============================================================"
  echo ""
  if [ "$MODE" = "single" ]; then
    info "Connect to the Spark container using:"
     echo "          docker exec -it spark bash"
  else
    info "Connect to the Spark master container:"
     echo "          docker exec -it spark-master bash"
  fi
  echo ""
  info "Useful commands inside container:"
  if [ "$MODE" = "single" ]; then
    echo "        - Spark Shell   : spark-shell"
    echo "        - PySpark       : pyspark"
  else
    echo "        - Spark Shell   : spark-shell --master spark://hadoop.spark:7077"
    echo "        - PySpark       : pyspark --master spark://hadoop.spark:7077"
  fi
  echo "        - Beeline       : beeline -u jdbc:hive2://localhost:10000"
  echo "        - HDFS          : hdfs dfs -ls /"
  echo ""
  echo "============================================================"
else
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
  echo "     docker exec $PRIMARY_CONTAINER ps aux | grep -E 'java|hdfs'"
  echo ""
  echo "  2. Check logs:"
  echo "     docker logs $PRIMARY_CONTAINER"
  echo "     docker exec $PRIMARY_CONTAINER tail -50 /tmp/root/metastore.log"
  echo "     docker exec $PRIMARY_CONTAINER tail -50 /tmp/root/hiveserver2.log"
  echo ""
  echo "  3. Reinitialize Hive schema:"
  echo "     docker exec $PRIMARY_CONTAINER schematool -dbType postgres -initSchema"
  echo ""
  echo "  4. Restart everything:"
  echo "     docker-compose -f $COMPOSE_FILE down && ./setup-spark.sh --build --run --node-type $MODE"
  echo ""
  echo "============================================================"
  exit 1
fi
