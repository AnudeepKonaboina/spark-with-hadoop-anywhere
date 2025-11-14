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
  
  docker pull docker4ops/hive-metastore:hive-4.0.0
  docker pull docker4ops/spark-with-hadoop:spark-3.5.2_hadoop-3.3.6_hive-4.0.0_scala-2.12

  echo "Pull complete!"
  
  # Set environment variables to use Docker Hub images (default)
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-4.0.0"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-3.5.2_hadoop-3.3.6_hive-4.0.0_scala-2.12"
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
  echo "   - Spark UI        : http://localhost:4040"
  echo "   - Spark History   : http://localhost:8090"
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
#!/usr/bin/env bash

# Ensure we are running under bash even if invoked via `sh`
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# =============================================================================
# Spark with Hadoop Setup Script
# =============================================================================
# Description: Sets up Spark 3.5.2 with Hadoop 3.3.6 and Hive 4.0.0 on Scala 2.12
# Requirements: Docker, Docker Compose
# 
# Usage:
#   ./setup-spark.sh --run              # Pull images from DockerHub
#   ./setup-spark.sh --build --run      # Build images locally
#
# Components:
#   - Java 17 (Adoptium Temurin)
#   - Spark 3.5.2 (Scala 2.12)
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
STOP_MODE=false
MODE="single" # single | multi

while [[ $# -gt 0 ]]; do
  case $1 in
    --build) BUILD_MODE=true; shift ;;
    --run) RUN_MODE=true; shift ;;
    --stop) STOP_MODE=true; shift ;;
    --node-type=*) MODE="${1#*=}"; shift ;;
    --node-type)
      if [ "${2:-}" = "" ]; then
        echo "Error: --node-type requires a value: single|multi"; exit 1
      fi
      MODE="$2"; shift 2 ;;
    --single) MODE="single"; shift ;;
    --multi) MODE="multi"; shift ;;
    *)
      echo "Error: Unknown option '$1'"
      echo ""
      echo "Usage: $0 [--build] [--run] [--stop] [--node-type single|multi]"
      echo "  --run                 : Pull images from DockerHub (fast)"
      echo "  --build --run         : Build images locally (slow, for development)"
      echo "  --stop                : Stop and remove the selected stack"
      echo "Optional:"
      echo "  --node-type single    : Single container (default)"
      echo "  --node-type multi     : Spark master + workers"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ "$RUN_MODE" = false ] && [ "$STOP_MODE" = false ]; then
  echo "Error: Please specify --run or --stop"
  echo "Usage: $0 [--build] --run | --stop [--node-type single|multi]"
  exit 1
fi

if [ "$BUILD_MODE" = true ] && [ "$RUN_MODE" = false ]; then
  echo "Error: --build requires --run"
  exit 1
fi

# -----------------------------------------------------------------------------
# Early stop
# -----------------------------------------------------------------------------
if [ "$STOP_MODE" = true ]; then
  print_section "Stopping services (auto-detected)"
  if docker ps --format '{{.Names}}' | grep -q '^spark$'; then
    docker-compose -f docker-compose.single.yml down
  elif docker ps --format '{{.Names}}' | grep -q '^spark-master$'; then
    docker-compose -f docker-compose.yml down
  else
    docker-compose -f docker-compose.single.yml down || true
    docker-compose -f docker-compose.yml down || true
  fi
  echo "Done."
  exit 0
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
  docker pull docker4ops/spark-with-hadoop:spark-3.5.2_hadoop-3.3.6_hive-4.0.0_scala-2.12
  
  export HIVE_METASTORE_IMAGE="docker4ops/hive-metastore:hive-4.0.0"
  export SPARK_HADOOP_IMAGE="docker4ops/spark-with-hadoop:spark-3.5.2_hadoop-3.3.6_hive-4.0.0_scala-2.12"
fi

# -----------------------------------------------------------------------------
# Step 2: Start Containers (single or multi)
# -----------------------------------------------------------------------------

print_section "Starting containers"
COMPOSE_FILE="docker-compose.single.yml"
if [ "$MODE" = "multi" ]; then
  COMPOSE_FILE="docker-compose.yml"
fi
docker-compose -f "$COMPOSE_FILE" up -d --remove-orphans

if [ "$MODE" = "single" ]; then
  # Wait for containers to be running
  wait_for_condition "containers" \
    "docker inspect -f '{{.State.Status}}' spark 2>/dev/null | grep -q running && \
     docker inspect -f '{{.State.Status}}' hive_metastore 2>/dev/null | grep -q running" \
    30 2
else
  wait_for_condition "containers" \
    "docker inspect -f '{{.State.Status}}' spark-master 2>/dev/null | grep -q running && \
     docker inspect -f '{{.State.Status}}' hive_metastore 2>/dev/null | grep -q running" \
    30 2
fi

# -----------------------------------------------------------------------------
# Step 3: Initialize HDFS (single only)
# -----------------------------------------------------------------------------

if [ "$MODE" = "single" ]; then
  print_section "Initializing HDFS"
  docker exec spark bash -c '
    hdfs namenode -format -force &&
    HDFS_NAMENODE_USER=root HDFS_DATANODE_USER=root HDFS_SECONDARYNAMENODE_USER=root start-dfs.sh &&
    sleep 5 &&
    hdfs dfs -mkdir -p /tmp &&
    hdfs dfs -mkdir -p /user/hive/warehouse &&
    hdfs dfs -chmod g+w /user/hive/warehouse
  ' >/dev/null 2>&1 || true
  echo "✓ HDFS initialized"
fi

# -----------------------------------------------------------------------------
# Step 4: Initialize Hive Metastore Schema (single only)
# -----------------------------------------------------------------------------

if [ "$MODE" = "single" ]; then
  echo ""
  echo "Waiting for PostgreSQL to be ready..."

  # Wait for PostgreSQL (critical for schema initialization)
  for i in $(seq 1 20); do
    if docker exec hive_metastore pg_isready -U hive -d metastore >/dev/null 2>&1; then
      echo "PostgreSQL responding, waiting for full initialization..."
      sleep 15
      echo "✓ PostgreSQL ready"
      break
    fi
    sleep 2
  done

  echo "Checking Hive metastore schema..."

  # Check if schema already exists
  SCHEMA_CHECK=$(docker exec spark bash -c 'schematool -dbType postgres -info 2>&1 | grep "Metastore schema version"' || echo "")

  if [ -n "$SCHEMA_CHECK" ]; then
    echo "✓ Hive schema already exists"
  else
    echo "Initializing Hive schema (this takes ~20 seconds)..."
  docker exec spark bash -c 'schematool -dbType postgres -initSchema' >/dev/null 2>&1
  
  # Verify initialization succeeded
  sleep 2
  SCHEMA_CHECK=$(docker exec spark bash -c 'schematool -dbType postgres -info 2>&1 | grep "Metastore schema version"' || echo "")
  if [ -n "$SCHEMA_CHECK" ]; then
    echo "✓ Schema initialized successfully"
  else
    echo "⚠ Schema initialization failed, retrying once..."
    docker exec spark bash -c 'schematool -dbType postgres -initSchema' >/dev/null 2>&1
    sleep 2
    SCHEMA_CHECK=$(docker exec spark bash -c 'schematool -dbType postgres -info 2>&1 | grep "Metastore schema version"' || echo "")
    if [ -n "$SCHEMA_CHECK" ]; then
      echo "✓ Schema initialized successfully on retry"
    else
      echo "✗ Schema initialization failed - Hive may not work properly"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Step 5: Start Hive Services
# -----------------------------------------------------------------------------

print_section "Starting Hive Metastore and HiveServer2"

# Avoid premature exits during service startup waits
set +e

# Kill any existing Hive processes
docker exec spark bash -c 'pkill -9 -f "HiveMetaStore|HiveServer2" 2>/dev/null || true'
sleep 1

# Start Metastore reliably
echo "Starting Hive Metastore..."
docker exec spark bash -c 'nohup hive --service metastore >/tmp/root/metastore.log 2>&1 & echo $! > /tmp/root/metastore.pid && disown' >/dev/null 2>&1 || true

# Wait for Metastore (port 9083) with hard timeout (~3 min) and log-based readiness
echo "Waiting for Metastore to start..."
METASTORE_READY=false
META_START_TS=$(date +%s)
for i in $(seq 1 90); do
  if docker exec spark bash -c 'ss -tulpn 2>/dev/null | grep -q 9083 || grep -q "Starting Hive Metastore Server" /tmp/root/metastore.log 2>/dev/null'; then
    METASTORE_READY=true; echo "✓ Metastore ready"; break
  fi
  NOW=$(date +%s); ELAPSED=$((NOW - META_START_TS))
  if (( i % 10 == 0 )); then echo "  Still waiting for Metastore... (${ELAPSED}s elapsed)"; fi
  sleep 2
done
if [ "$METASTORE_READY" != true ]; then
  echo "✗ Metastore did not start in time. Last log lines:"; docker exec spark bash -c 'tail -80 /tmp/root/metastore.log || true'
  exit 1
fi

# Start HiveServer2 reliably
echo "Starting HiveServer2..."
docker exec spark bash -c 'nohup hive --service hiveserver2 >/tmp/root/hiveserver2.log 2>&1 & echo $! > /tmp/root/hiveserver2.pid && disown' >/dev/null 2>&1 || true

# Wait for HiveServer2 (port 10000) - this takes longer (min 180s visible wait, max 600s)
echo "Waiting for HiveServer2 to start (up to 3 minutes)..."
HS2_READY=false
HS2_START_TS=$(date +%s)
HS2_PORT_SEEN=false
MAX_WAIT_SEC=600
while :; do
  if docker exec spark bash -c 'ss -tulpn 2>/dev/null | grep -q 10000 || grep -q "Starting ThriftBinaryCLIService on port" /tmp/root/hive*.log 2>/dev/null || grep -q "Service:HiveServer2 is started" /tmp/root/hive*.log 2>/dev/null'; then
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
  echo "✗ HiveServer2 did not start in time. Last log lines:"; docker exec spark bash -c 'tail -80 /tmp/root/hiveserver2.log || true'
  exit 1
fi

# Extra: wait for JDBC readiness (SQL query responds)
echo "Waiting for HiveServer2 JDBC to become responsive..."
JDBC_READY=false
JDBC_START_TS=$(date +%s)
for i in $(seq 1 180); do
  if docker exec spark bash -c 'beeline -u jdbc:hive2://localhost:10000 -e "show databases;" >/dev/null 2>&1'; then
    JDBC_READY=true; echo "✓ HiveServer2 JDBC ready"; break
  fi
  NOW=$(date +%s); ELAPSED=$((NOW - JDBC_START_TS))
  if (( i % 10 == 0 )); then echo "  Still waiting for JDBC... (${ELAPSED}s elapsed)"; fi
  sleep 2
done
if [ "$JDBC_READY" != true ]; then
  echo "✗ HiveServer2 JDBC not responsive in time. Last HS2 log lines:"; docker exec spark bash -c 'tail -80 /tmp/root/hiveserver2.log || true'
  exit 1
fi

# Re-enable strict mode for health checks
set -e

# -----------------------------------------------------------------------------
# Validate All Services Before Completion
# -----------------------------------------------------------------------------

echo ""
echo "Running final health checks..."

# Initialize error tracking
ERRORS=()

# Test 1: HDFS (non-blocking, process-based)
echo "  Testing HDFS..."
if docker exec spark bash -c 'ps aux | grep -q "org.apache.hadoop.hdfs.server.namenode.NameNode" && ps aux | grep -q "org.apache.hadoop.hdfs.server.datanode.DataNode"'; then
  echo "    ✓ HDFS daemons are running"
else
  echo "    ⚠ HDFS daemons not detected, performing quick dfs check..."
  HDFS_ERROR=$(docker exec spark bash -c 'timeout 15s hdfs dfs -ls / 2>&1' | grep -i "error\|exception\|timed out" | head -1)
  if docker exec spark bash -c 'timeout 15s hdfs dfs -ls / >/dev/null 2>&1'; then
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

# Test 2: Spark
echo "  Testing Spark..."
SPARK_VERSION=$(docker exec spark bash -c 'timeout 20s spark-submit --version 2>&1 | grep -E "version" | head -1' || echo "")
if docker exec spark bash -c 'timeout 20s spark-submit --version 2>&1 | grep -q "version 3.5.2"'; then
  echo "    ✓ Spark is working"
else
  echo "    ✗ Spark test failed"
  if [ -n "$SPARK_VERSION" ]; then
    ERRORS+=("Spark: Expected version 3.5.2, found: $SPARK_VERSION")
  else
    ERRORS+=("Spark: Version check failed - spark-submit not responding within timeout")
  fi
fi

# Test 3: Hive Metastore
echo "  Testing Hive Metastore..."
if docker exec spark bash -c 'ss -tulpn 2>/dev/null | grep -q ":9083"'; then
  echo "    ✓ Hive Metastore is working"
else
  echo "    ✗ Hive Metastore not running"
  METASTORE_PROCESS=$(docker exec spark bash -c 'ps aux | grep "metastore.HiveMetaStore" | grep -v grep' || echo "")
  if [ -n "$METASTORE_PROCESS" ]; then
    ERRORS+=("Hive Metastore: Process running but port 9083 not listening (still initializing?)")
  else
    ERRORS+=("Hive Metastore: Process not running - check logs: docker exec spark tail -50 /tmp/root/metastore.log")
  fi
fi

# Test 4: HiveServer2
echo "  Testing HiveServer2..."
if docker exec spark bash -c 'ss -tulpn 2>/dev/null | grep -q ":10000"'; then
  echo "    ✓ HiveServer2 is working"
else
  echo "    ✗ HiveServer2 not running"
  HIVESERVER_PROCESS=$(docker exec spark bash -c 'ps aux | grep "HiveServer2" | grep -v grep' || echo "")
  if [ -n "$HIVESERVER_PROCESS" ]; then
    ERRORS+=("HiveServer2: Process running but port 10000 not listening (still initializing?)")
  else
    ERRORS+=("HiveServer2: Process not running - check logs: docker exec spark tail -50 /tmp/root/hiveserver2.log")
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
  echo "    docker exec -it spark bash"
  echo ""
  echo "[+] Run the following commands to start the following services:"
  echo "  - Spark Shell   : spark-shell"
  echo "  - PySpark       : pyspark"
  echo "  - Hive(Beeline) : beeline -u jdbc:hive2://localhost:10000"
  echo "  - HDFS          : hdfs dfs -ls /"
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
  echo "     docker exec spark tail -50 /tmp/root/metastore.log"
  echo "     docker exec spark tail -50 /tmp/root/hiveserver2.log"
  echo ""
  echo "  3. Reinitialize Hive schema:"
  echo "     docker exec spark schematool -dbType postgres -initSchema"
  echo ""
  echo "  4. Restart everything:"
  echo "     docker-compose down && ./setup-spark.sh --build --run"
  echo ""
  echo "============================================================"
  exit 1
fi
