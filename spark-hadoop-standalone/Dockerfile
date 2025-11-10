FROM centos:7

ARG hadoop_version=2.10.1
ARG spark_version=2.4.7
ARG hive_version=2.1.1

# Update repository configurations and install all dependencies in one layer with cleanup
RUN cd /etc/yum.repos.d/ && \
    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-* && \
    yum update -y && \
    yum install -y epel-release && \
    yum install -y \
        curl \
        bash \
        java-1.8.0-openjdk-headless \
        openssh-server \
        openssh-clients \
        which \
        postgresql-jdbc \
        aria2 && \
    yum clean all && \
    rm -rf /var/cache/yum

################################################### Hadoop-client installation ###################################################################
RUN aria2c -x 16 -s 16 -k 1M https://archive.apache.org/dist/hadoop/core/hadoop-${hadoop_version}/hadoop-${hadoop_version}.tar.gz -o hadoop.tgz && \
    tar -xzf hadoop.tgz && \
    mv hadoop-${hadoop_version} /usr/bin/ && \
    rm hadoop.tgz && \
    # Remove unnecessary files to reduce size
    rm -rf /usr/bin/hadoop-${hadoop_version}/share/doc && \
    rm -rf /usr/bin/hadoop-${hadoop_version}/share/hadoop/*/sources && \
    rm -rf /usr/bin/hadoop-${hadoop_version}/share/hadoop/*/*.tar.gz

# set Hadoop environment variables
ENV JAVA_HOME=/usr/lib/jvm/jre-1.8.0-openjdk \
    HADOOP_HOME=/usr/bin/hadoop-${hadoop_version} \
    HADOOP_CONF_DIR=/usr/bin/hadoop-${hadoop_version}/etc/hadoop \
    HADOOP_MAPRED_HOME=/usr/bin/hadoop-${hadoop_version} \
    HADOOP_COMMON_HOME=/usr/bin/hadoop-${hadoop_version} \
    HADOOP_HDFS_HOME=/usr/bin/hadoop-${hadoop_version} \
    HADOOP_COMMON_LIB_NATIVE_DIR=/usr/bin/hadoop-${hadoop_version}/lib/native \
    YARN_HOME=/usr/bin/hadoop-${hadoop_version}

ENV PATH=${JAVA_HOME}/bin:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${PATH}

# set hadoop-env.sh and create folders in one layer
RUN echo "export JAVA_HOME=${JAVA_HOME}" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh && \
    echo "export HADOOP_HOME=${HADOOP_HOME}" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh && \
    echo "export HADOOP_CONF_DIR=${HADOOP_CONF_DIR}" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh && \
    mkdir -p /usr/bin/data/nameNode /usr/bin/data/dataNode /usr/bin/data/nameNodeSecondary /usr/bin/data/tmp ${HADOOP_HOME}/logs

COPY configs/core-site.xml ${HADOOP_HOME}/etc/hadoop/core-site.xml
COPY configs/hdfs-site.xml ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml
COPY configs/mapred-site.xml ${HADOOP_HOME}/etc/hadoop/mapred-site.xml
####################################################### Hadoop client install end ##########################################################################

##################################################### spark-standalone without Hadoop #####################################################################
RUN aria2c -x 16 -s 16 -k 1M https://archive.apache.org/dist/spark/spark-${spark_version}/spark-${spark_version}-bin-without-hadoop.tgz -o spark.tgz && \
    tar -xzf spark.tgz && \
    mv spark-${spark_version}-bin-without-hadoop /usr/bin/ && \
    mkdir /usr/bin/spark-${spark_version}-bin-without-hadoop/logs && \
    rm spark.tgz && \
    # Remove unnecessary files to reduce size
    rm -rf /usr/bin/spark-${spark_version}-bin-without-hadoop/examples && \
    rm -rf /usr/bin/spark-${spark_version}-bin-without-hadoop/data && \
    rm -rf /usr/bin/spark-${spark_version}-bin-without-hadoop/R

# set environment variables for spark
ENV SPARK_HOME=/usr/bin/spark-${spark_version}-bin-without-hadoop \
    SPARK_LOG_DIR=/usr/bin/spark-${spark_version}-bin-without-hadoop/logs

ENV PATH=${SPARK_HOME}/bin:${SPARK_HOME}/sbin:${PATH}

RUN export SPARK_DIST_CLASSPATH="$(hadoop classpath)" && \
    mv ${SPARK_HOME}/conf/spark-env.sh.template ${SPARK_HOME}/conf/spark-env.sh && \
    echo "export SPARK_DIST_CLASSPATH=\$(hadoop classpath)" >> ${SPARK_HOME}/conf/spark-env.sh && \
    echo "export SPARK_LOG_DIR=${SPARK_LOG_DIR}" >> ${SPARK_HOME}/conf/spark-env.sh && \
    mv ${SPARK_HOME}/conf/spark-defaults.conf.template ${SPARK_HOME}/conf/spark-defaults.conf && \
    echo "spark.eventLog.dir file:${SPARK_LOG_DIR}" >> ${SPARK_HOME}/conf/spark-defaults.conf && \
    echo "spark.history.fs.logDirectory file:${SPARK_LOG_DIR}" >> ${SPARK_HOME}/conf/spark-defaults.conf
########################################################spark-standalone installation end###########################################################################################

###########################################################hive client installation ###################################################################################################
RUN aria2c -x 16 -s 16 -k 1M https://archive.apache.org/dist/hive/hive-${hive_version}/apache-hive-${hive_version}-bin.tar.gz -o hive.tgz && \
    tar -xzf hive.tgz && \
    mv apache-hive-${hive_version}-bin /usr/bin/ && \
    rm -rf hive.tgz && \
    # Remove unnecessary files to reduce size
    rm -rf /usr/bin/apache-hive-${hive_version}-bin/examples && \
    rm -rf /usr/bin/apache-hive-${hive_version}-bin/hcatalog/share/doc

# set hive environment variables
ENV HIVE_HOME=/usr/bin/apache-hive-${hive_version}-bin
ENV PATH=${HIVE_HOME}/bin:${PATH}

RUN cp /usr/share/java/postgresql-jdbc.jar ${HIVE_HOME}/lib/ && \
    echo "export HADOOP_HOME=${HADOOP_HOME}" >> ${HADOOP_HOME}/bin/hive-config.sh

COPY configs/hive-site.xml /configs/hive-site.xml

#setting ssh key and sshd config
RUN ssh-keygen -f "$HOME/.ssh/id_rsa" -t rsa -N "" && \
    cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys" && \
    ssh-keygen -A && \
    sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -ri 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

COPY configs/config /usr/bin/config
RUN mv /usr/bin/config "$HOME/.ssh/" && chmod 600 "$HOME/.ssh/config"
############################################################ hive installtion end ###########################################################################################

# add startup script
COPY scripts/start-services.sh /usr/local/bin/start-services.sh
RUN chmod +x /usr/local/bin/start-services.sh

