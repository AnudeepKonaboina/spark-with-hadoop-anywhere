FROM postgres:11.12

RUN export LANGUAGE=en_US.UTF-8

# Schema files not required; schema is initialized by schematool at runtime
COPY configs/init-hive-db.sh /docker-entrypoint-initdb.d/init-user-db.sh
