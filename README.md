# Setup Spark with Hadoop on Docker

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/44436c70bdcf427abd4b2d60ef3900f2)](https://app.codacy.com/gh/AnudeepKonaboina/spark-with-hadoop-anywhere/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)

[![Spark](https://img.shields.io/badge/Spark-2.4.7-E25A1C?logo=apachespark&logoColor=white)](https://spark.apache.org/releases/spark-release-2-4-7.html)
[![Hadoop](https://img.shields.io/badge/Hadoop-2.10.1-66CCFF?logo=apachehadoop&logoColor=white)](https://hadoop.apache.org/releases.html)
[![Hive](https://img.shields.io/badge/Hive-2.1.1-FDEE21?logo=apachehive&logoColor=black)](https://hive.apache.org/releases.html)
[![Scala](https://img.shields.io/badge/Scala-2.11.12-DC322F?logo=scala&logoColor=white)](https://www.scala-lang.org/download/2.11.12.html)
[![Java](https://img.shields.io/badge/Java-8-007396?logo=openjdk&logoColor=white)](https://openjdk.org/projects/jdk/10/)
[![CentOS](https://img.shields.io/badge/CentOS-7-262577?logo=centos&logoColor=white)](https://wiki.centos.org/Manuals/ReleaseNotes/CentOS7)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-11.12-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/docs/11/release-11-12.html)


This project allows you to spin up a single/multi-node cluster locally, containing spark with hadoop and hive deployed on docker containers.
This can be used for exploring, developing and testing spark jobs on OSS spark with HDFS as storage, work with hive to run HQL queries and also execute HDFS commands.

# Pre-requisites

You need to have **docker** engine and **docker-compose** installed in your vm/local terminal. You need to have a **superuser(sudo)** permissions for installation

### Installation steps 

- To install docker on MacOS ,follow the below steps:

Install Homebrew
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install docker
```
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

brew install --cask docker
```


- To install docker on  Ubuntu/Debian – see: [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) · [Debian](https://docs.docker.com/engine/install/debian/)

- To install docker on Fedora/RHEL/CentOS – see: [Fedora](https://docs.docker.com/engine/install/fedora/) · [RHEL](https://docs.docker.com/engine/install/rhel/) · [CentOS](https://docs.docker.com/engine/install/centos/)

---
# Verify installation:
```commandline
docker --version
docker compose version
docker run hello-world
```


# Supported Services and Versions

| Service      | Version     |
| -----------  | ----------- |
| Spark        | 2.4.7       |
| Hadoop       | 2.10.1      |
| Hive         | 2.1.1       |



# Steps to setup
1. Clone the project and navigate to the main directory using the command below
   ```commandline
   git clone -b spark-2.4.7 https://github.com/AnudeepKonaboina/spark-with-hadoop-anywhere.git && cd spark-with-hadoop-anywhere/
   ```

2. Create the secrets password file (used by Postgres/Hive)
   ```commandline
   mkdir -p secrets
   echo "your_strong_password" > secrets/postgres_password.txt
   ```

3. Run the setup script. Below are two ways to start the setup script
   - Run  `sh setup-spark.sh --run`  to pull pre-built images from DockerHub (quick setup)
   - Run  `sh setup-spark.sh --build --run`  to build images locally from scratch and run

     **Note:** The `--build` flag must always be used with `--run `. 


      #### Cluster mode (optional):
     
      You can also select cluster mode optionally  .There are two types of cluster modes supported.
      - **Single node (default)**: A single container with Spark + HDFS + Hive. Default mode if nothing is specified
      - **Multi node**   : Spark master + 2 workers with shared HDFS on master.

      Select mode with option `--node-type`:
      - Single: `sh setup-spark.sh --run --node-type single`
      - Multi:  `sh setup-spark.sh --run --node-type multi`

      If `--node-type` is omitted, single is used by default.

### Examples:

#### **Option 1: Quick Setup (Pull's images from DockerHub)**
```commandline
sh setup-spark.sh --run --node-type {single|multi}
```
  This will:
  - Pull pre-built images from Docker Hub
  - Starts a standalone spark cluster singe/multi node based on your choice
  - Initialize's HDFS and Hive
  - Quick and easy setup - recommended for most users


#### **Option 2: Build's images locally from scratch using Dockerfile**
```commandline
sh setup-spark.sh --build --run --node-type {single|multi}
```
  This will:
  - Build Docker images locally from Dockerfiles
  - Use the locally built images and starts a standalone spark cluster singe/multi node based on your choice
  - Initialize's HDFS and Hive
  - Useful if you need to customize the Dockerfiles



4. After the setup is completed you will have containers started

      If you used **`--run`** option (pulled from DockerHub), you'll see:
      ```commandline
      anudeep.k@SHELL% docker images
      REPOSITORY                     TAG                                    IMAGE ID       CREATED             SIZE
      docker4ops/spark-with-hadoop   spark-3.1.1_hadoop-3.2.0_hive-3.1.1    4c69c4d0041d   About an hour ago   4.24GB
      docker4ops/hive-metastore      hive-3.1.1                             31287c798b1d   About an hour ago   286MB
      ```
      
      If you used **`--build --run`** option (built locally), you'll see:
      ```commandline
      anudeep.k@SHELL% docker images
      REPOSITORY                     TAG                                    IMAGE ID       CREATED             SIZE
      spark-with-hadoop              local                                  4c69c4d0041d   About an hour ago   4.24GB
      hive-metastore                 local                                  31287c798b1d   About an hour ago   286MB
      ```
---
### Once the setup is complete you will see containers running as shown below

#### Single node:
```commandline
anudeep.k@SHELL% docker ps
CONTAINER ID   IMAGE                     COMMAND                  CREATED         STATUS         PORTS                                                                                                                                                                                                          NAMES
1af5afd31789   spark-with-hadoop:local   "/usr/local/bin/star…"   3 minutes ago   Up 3 minutes   23/tcp, 0.0.0.0:4040-4041->4040-4041/tcp, [::]:4040-4041->4040-4041/tcp, 0.0.0.0:2222->22/tcp, [::]:2222->22/tcp, 0.0.0.0:8089->8088/tcp, [::]:8089->8088/tcp, 0.0.0.0:8090->18080/tcp, [::]:8090->18080/tcp   spark
c8c3e725a73c   hive-metastore:local      "docker-entrypoint.s…"   3 minutes ago   Up 3 minutes   5432/tcp                                                                                                                                                                                                       hive_metastore

```
#### Multi node:

```commandline

CONTAINER ID   IMAGE                                                               COMMAND                   CREATED         STATUS         PORTS                                                                                                                                                                                                                                                                                                NAMES
60e52fdc6bc5   docker4ops/spark-with-hadoop:spark-2.4.7_hadoop-2.10.1_hive-2.1.1   "bash -lc '\n  ${SPAR…"   6 minutes ago   Up 6 minutes                                                                                                                                                                                                                                                                                                        spark-worker-2
973ee17a76e8   docker4ops/spark-with-hadoop:spark-2.4.7_hadoop-2.10.1_hive-2.1.1   "bash -lc '\n  ${SPAR…"   6 minutes ago   Up 6 minutes                                                                                                                                                                                                                                                                                                        spark-worker-1
18bd26ade9ac   docker4ops/spark-with-hadoop:spark-2.4.7_hadoop-2.10.1_hive-2.1.1   "bash -lc '\n  /usr/l…"   6 minutes ago   Up 6 minutes   0.0.0.0:4040-4041->4040-4041/tcp, [::]:4040-4041->4040-4041/tcp, 0.0.0.0:7077->7077/tcp, [::]:7077->7077/tcp, 0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp, 0.0.0.0:50070->50070/tcp, [::]:50070->50070/tcp, 0.0.0.0:2222->22/tcp, [::]:2222->22/tcp, 0.0.0.0:8090->18080/tcp, [::]:8090->18080/tcp   spark-master
12fcb76b3af2   docker4ops/hive-metastore:hive-2.1.1                                "docker-entrypoint.s…"    6 minutes ago   Up 6 minutes   5432/tcp                                                                                                                                                                                                                                                                                             hive_metastore
```

5. Connect to containers

##### Single node:
```commandline
docker exec -it spark bash 
```

##### Multi node (master):
```commandline
docker exec -it spark-master bash
```


6. Once you get into the container,you will have spark ,hdfs and hive service inside the container ready for you to use.



# How to use it

#### To run hive inside container:
```commandline
[root@hadoop /]# hive
which: no hbase in (/usr/bin/apache-hive-2.1.1-bin/bin:/usr/bin/spark-2.4.7-bin-without-hadoop/bin:/usr/bin/spark-2.4.7-bin-without-hadoop/sbin:/usr/bin/hadoop-2.10.1/bin:/usr/bin/hadoop-2.10.1/sbin:/usr/lib/jvm/java-1.8.0-openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin)
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/bin/apache-hive-2.1.1-bin/lib/log4j-slf4j-impl-2.4.1.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/bin/hadoop-2.10.1/share/hadoop/common/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.apache.logging.slf4j.Log4jLoggerFactory]

Logging initialized using configuration in jar:file:/usr/bin/apache-hive-2.1.1-bin/lib/hive-common-2.1.1.jar!/hive-log4j2.properties Async: true
Hive-on-MR is deprecated in Hive 2 and may not be available in the future versions. Consider using a different execution engine (i.e. spark, tez) or using Hive 1.X releases.
hive>
```

#### To run hdfs commands within container:
```commandline
[root@hadoop /]# hdfs dfs -ls /
21/06/02 12:49:26 WARN util.NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
Found 2 items
drwxr-xr-x   - root supergroup          0 2021-06-02 12:48 /tmp
drwxr-xr-x   - root supergroup          0 2021-06-02 12:22 /user
[root@hadoop /]#
```

#### To run spark shell within container:
```commandline
[root@hadoop /]# spark-shell
25/10/02 12:50:55 WARN util.NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
Setting default log level to "WARN".
To adjust logging level use sc.setLogLevel(newLevel). For SparkR, use setLogLevel(newLevel).
Spark context Web UI available at http://hadoop.spark:4040
Spark context available as 'sc' (master = local[*], app id = local-1622638263693).
Spark session available as 'spark'.
Welcome to
      ____              __
     / __/__  ___ _____/ /__
    _\ \/ _ \/ _ `/ __/  '_/
   /___/ .__/\_,_/_/ /_/\_\   version 2.4.7
      /_/

Using Scala version 2.11.12 (OpenJDK 64-Bit Server VM, Java 1.8.0_292)
Type in expressions to have them evaluated.
Type :help for more information.

scala>
```

#### In multi node mode, connect to the cluster master:
```commandline
[root@hadoop /]# spark-shell --master spark://hadoop.spark:7077
25/11/15 10:55:42 WARN util.NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
Setting default log level to "WARN".
To adjust logging level use sc.setLogLevel(newLevel). For SparkR, use setLogLevel(newLevel).
Spark context Web UI available at http://hadoop.spark:4040
Spark context available as 'sc' (master = spark://hadoop.spark:7077, app id = app-20251115105544-0000).
Spark session available as 'spark'.
Welcome to
      ____              __
     / __/__  ___ _____/ /__
    _\ \/ _ \/ _ `/ __/  '_/
   /___/ .__/\_,_/_/ /_/\_\   version 2.4.7
      /_/
         
Using Scala version 2.11.12 (OpenJDK 64-Bit Server VM, Java 1.8.0_412)
Type in expressions to have them evaluated.
Type :help for more information.

scala> 

```
#### To control parallelism (Spark Standalone):
```commandline
spark-shell --master spark://hadoop.spark:7077 --executor-cores 1 --total-executor-cores 2
```

#### To run hive using beeline:
```commandline
[root@hadoop /]# beeline
which: no hbase in (/usr/bin/apache-hive-2.1.1-bin/bin:/usr/bin/spark-2.4.7-bin-without-hadoop/bin:/usr/bin/spark-2.4.7-bin-without-hadoop/sbin:/usr/bin/hadoop-2.10.1/bin:/usr/bin/hadoop-2.10.1/sbin:/usr/lib/jvm/java-1.8.0-openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin)
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/bin/apache-hive-2.1.1-bin/lib/log4j-slf4j-impl-2.4.1.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/bin/hadoop-2.10.1/share/hadoop/common/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.apache.logging.slf4j.Log4jLoggerFactory]
Beeline version 2.1.1 by Apache Hive
beeline> !connect jdbc:hive2://
Connecting to jdbc:hive2://
Enter username for jdbc:hive2://: hive
Enter password for jdbc:hive2://: ****
21/06/02 14:39:20 [main]: WARN util.NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
21/06/02 14:39:22 [main]: WARN session.SessionState: METASTORE_FILTER_HOOK will be ignored, since hive.security.authorization.manager is set to instance of HiveAuthorizerFactory.
Connected to: Apache Hive (version 2.1.1)
Driver: Hive JDBC (version 2.1.1)
25/10/02 14:39:22 [main]: WARN jdbc.HiveConnection: Request to set autoCommit to false; Hive does not support autoCommit=false.
Transaction isolation: TRANSACTION_REPEATABLE_READ
0: jdbc:hive2://>
```


# Clean-up commands:

Once your testing is completed ,its time to clean up your containers. Use the below steps for cleaning up the conatiners and images 

```commandline
sh setup-spark.sh --stop
```




# Author
Anudeep Konaboina <krantianudeep@gmail.com>


