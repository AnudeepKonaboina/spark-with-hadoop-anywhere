# Setup Spark with Hadoop on Docker

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/44436c70bdcf427abd4b2d60ef3900f2)](https://app.codacy.com/gh/AnudeepKonaboina/spark-with-hadoop-anywhere/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)

[![Spark](https://img.shields.io/badge/Spark-2.4.7-E25A1C?logo=apachespark&logoColor=white)](https://spark.apache.org/releases/spark-release-2-4-7.html)
[![Hadoop](https://img.shields.io/badge/Hadoop-2.10.1-66CCFF?logo=apachehadoop&logoColor=white)](https://hadoop.apache.org/releases.html)
[![Hive](https://img.shields.io/badge/Hive-2.1.1-FDEE21?logo=apachehive&logoColor=black)](https://hive.apache.org/releases.html)
[![Scala](https://img.shields.io/badge/Scala-2.11.12-DC322F?logo=scala&logoColor=white)](https://www.scala-lang.org/download/2.11.12.html)
[![CentOS](https://img.shields.io/badge/CentOS-7-262577?logo=centos&logoColor=white)](https://wiki.centos.org/Manuals/ReleaseNotes/CentOS7)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-11.12-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/docs/11/release-11-12.html)


This project allows you to spin up an environment containing spark-standalone with hadoop and hive leveraged inside docker containers.This can be used for exploring developing and testing  spark jobs on OSS spark with HDFS as storage , work with hive to run HQL queries and also execute HDFS commands.

## Prerequisites
- You need to have **docker** engine and **docker-compose** installed in your vm/local terminal. You need to have a superuser(sudo) permissions for installation

### Installation steps 

- To install docker on MacOS

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


#### Verify installation:
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




# Setps to setup
1. Clone the project abd navigate to the main directory
```commandline
git clone -b spark-2.4.7 https://github.com/AnudeepKonaboina/spark-with-hadoop-anywhere.git && cd spark-with-hadoop-anywhere/
```

2. Create the secrets password file (used by Postgres/Hive)
```commandline
mkdir -p secrets
echo "your_strong_password" > secrets/postgres_password.txt
```

3. Run the script file
```commandline
sh setup-spark.sh
```

4. After the setup is completed you will have two containers started as shown below
```commandline
anudeep.k@SHELL% docker images
REPOSITORY                     TAG                                    IMAGE ID       CREATED             SIZE
docker4ops/spark-with-hadoop   spark-2.4.7_hadoop-2.10.1_hive-2.1.1   4c69c4d0041d   About an hour ago   4.24GB
docker4ops/hive-metastore      hive-2.1.1                             31287c798b1d   About an hour ago   286MB                                                                                                                                                                                          hive_metastore
```

5. SSH into the spark container using the command
```commandline
docker exec -it spark bash 
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
21/06/02 12:50:55 WARN util.NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
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
21/06/02 14:39:22 [main]: WARN jdbc.HiveConnection: Request to set autoCommit to false; Hive does not support autoCommit=false.
Transaction isolation: TRANSACTION_REPEATABLE_READ
0: jdbc:hive2://>
```


# Clean-up commands:

Once your testing is completed ,its time to clean up your containers. Use the below steps for cleanup

1. Run **`docker-compose down`** to clean stop all the running containers
````
anudeep.k@SHELL spark-with-hadoop-anywhere % docker-compose down
[+] Running 3/3
 ✔ Container spark                             Removed                                                                                               10.4s 
 ✔ Container hive_metastore                    Removed                                                                                                0.1s 
 ✔ Network spark-with-hadoop-anywhere_default  Removed
````

2. Run the command **`docker rmi -f $(docker images -a -q)`** to remove all the images you pulled. You can also run `docker system prune` to do a disk cleanup and reclaim space

```aiignore
anudeep.k@SHELL spark-with-hadoop-anywhere % docker rmi -f $(docker images -a -q)
Untagged: docker4ops/spark-with-hadoop:spark-2.4.7_hadoop-2.10.1_hive-2.1.1
Deleted: sha256:4c69c4d0041d625f1f6d16649c56517db565bc429dca8320fc1c86082d33bc5e
Untagged: docker4ops/hive-metastore:hive-2.1.1
Deleted: sha256:31287c798b1de021668fce9370994ae3b8a7f78e9e3d05cbef7816a0db629e78

anudeep.k@SHELL spark-with-hadoop-anywhere % docker system prune                 
WARNING! This will remove:
  - all stopped containers
  - all networks not used by at least one container
  - all dangling images
  - unused build cache

Are you sure you want to continue? [y/N] y
Total reclaimed space: 0B

```



# Author
Anudeep Konaboina <krantianudeep@gmail.com>


