#!/usr/bin/env bash
set -euo pipefail

# Ensure SSH host keys exist and start sshd
ssh-keygen -A >/dev/null 2>&1 || true
/usr/sbin/sshd || true

# Hadoop 3.x requires explicit daemon users when running as root
export HDFS_NAMENODE_USER=root
export HDFS_DATANODE_USER=root
export HDFS_SECONDARYNAMENODE_USER=root

# If HDFS is not initialized, run interactive NameNode format
if [ ! -d "/usr/bin/data/nameNode/current" ]; then
  hdfs namenode -format
fi

# Start HDFS daemons
start-dfs.sh

# Wait for HDFS NameNode RPC to be available before using hdfs dfs (max ~60s)
for i in {1..60}; do
  if (echo > /dev/tcp/hadoop.spark/9000) >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Prepare HDFS directories for Hive
hdfs dfs -mkdir -p /tmp || true
hdfs dfs -chmod 1777 /tmp || true
hdfs dfs -mkdir -p /user/hive/warehouse || true
hdfs dfs -chmod g+w /user/hive/warehouse || true

# Render hive-site.xml from template using secret if available
HIVE_PW_FILE="/run/secrets/postgres_password"
HIVE_PW="${HIVE_DB_PASSWORD:-}"
if [ -z "${HIVE_PW}" ] && [ -f "${HIVE_PW_FILE}" ]; then
  HIVE_PW="$(cat "${HIVE_PW_FILE}")"
fi
if [ -n "${HIVE_PW}" ] && [ -f "${HIVE_HOME}/conf/hive-site.xml" ]; then
  cp "${HIVE_HOME}/conf/hive-site.xml" "${HIVE_HOME}/conf/hive-site.xml.bak" || true
fi
if [ -n "${HIVE_PW}" ] && [ -f "/configs/hive-site.xml" ]; then
  sed "s/@@HIVE_DB_PASSWORD@@/${HIVE_PW//\//\\/}/g" /configs/hive-site.xml > "${HIVE_HOME}/conf/hive-site.xml"
  cp "${HIVE_HOME}/conf/hive-site.xml" "$SPARK_HOME/conf/hive-site.xml"
fi

# Wait for metastore DB DNS and TCP readiness (max ~60s)
for i in {1..60}; do
  if getent hosts hive-metastore >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
for i in {1..60}; do
  if (echo > /dev/tcp/hive-metastore/5432) >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Start Hive Metastore and HiveServer2
hive --service metastore &
sleep 15
hive --service hiveserver2 &

# Keep the container running
tail -f /dev/null


