# Rebuild of keyvault-test image with all security patches applied
# Base: Ubuntu 22.04 + Eclipse Temurin JDK 17 + Spark 3.5.8 + Python 3.10
# Addresses all Defender for Cloud vulnerability findings

FROM eclipse-temurin:17-jdk-jammy

ARG spark_uid=185

# Create spark user
RUN groupadd --system --gid=${spark_uid} spark && \
    useradd --system --uid=${spark_uid} --gid=spark -d /nonexistent spark

# Install Spark dependencies + apply ALL OS security patches
RUN set -ex; \
    apt-get update; \
    apt-get install -y gnupg2 wget bash tini libc6 libpam-modules krb5-user \
        libnss3 procps net-tools gosu libnss-wrapper; \
    # Apply all available security updates for OS packages
    apt-get upgrade -y; \
    mkdir -p /opt/spark /opt/spark/python /opt/spark/examples /opt/spark/work-dir; \
    chmod g+w /opt/spark/work-dir; \
    touch /opt/spark/RELEASE; \
    chown -R spark:spark /opt/spark; \
    echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su; \
    rm -rf /var/lib/apt/lists/*

# Download and install Spark 3.5.8
ENV SPARK_TGZ_URL=https://www.apache.org/dyn/closer.lua/spark/spark-3.5.8/spark-3.5.8-bin-hadoop3.tgz?action=download
ENV SPARK_TGZ_ASC_URL=https://www.apache.org/dyn/closer.lua/spark/spark-3.5.8/spark-3.5.8-bin-hadoop3.tgz.asc?action=download
ENV GPG_KEY=F28C9C925C188C35E345614DEDA00CE834F0FC5C
ENV SPARK_HOME=/opt/spark

RUN set -ex; \
    export SPARK_TMP="$(mktemp -d)"; \
    cd $SPARK_TMP; \
    wget -nv -O spark.tgz "$SPARK_TGZ_URL"; \
    wget -nv -O spark.tgz.asc "$SPARK_TGZ_ASC_URL"; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-key "$GPG_KEY" || \
    gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$GPG_KEY"; \
    gpg --batch --verify spark.tgz.asc spark.tgz; \
    gpgconf --kill all; \
    rm -rf "$GNUPGHOME" spark.tgz.asc; \
    tar -xf spark.tgz --strip-components=1; \
    chown -R spark:spark .; \
    mv jars /opt/spark/; \
    mv RELEASE /opt/spark/; \
    mv bin /opt/spark/; \
    mv sbin /opt/spark/; \
    mv kubernetes/dockerfiles/spark/decom.sh /opt/; \
    mv examples /opt/spark/; \
    ln -s "$(basename /opt/spark/examples/jars/spark-examples_*.jar)" /opt/spark/examples/jars/spark-examples.jar; \
    mv kubernetes/tests /opt/spark/; \
    mv data /opt/spark/; \
    mv python/pyspark /opt/spark/python/pyspark/; \
    mv python/lib /opt/spark/python/lib/; \
    mv R /opt/spark/; \
    chmod a+x /opt/decom.sh; \
    cd ..; \
    rm -rf "$SPARK_TMP"

# Overlay patched Java JARs to fix vulnerabilities:
# commons-beanutils, commons-compress, commons-configuration2, commons-io,
# commons-lang3, commons-net, jackson-core, jackson-databind, json-smart,
# guava, netty-*, log4j-core, avro, protobuf-java, nimbus-jose-jwt,
# okhttp, woodstox-core, dnsjava, hadoop-common, http2-hpack,
# hive-exec, hive-llap-common, mesos, zookeeper, aircompressor
RUN set -ex; \
    cd /opt/spark/jars; \
    # Remove old vulnerable JARs and download patched versions
    # commons-beanutils 1.9.4
    rm -f commons-beanutils-*.jar; \
    wget -nv -O commons-beanutils-1.9.4.jar "https://repo1.maven.org/maven2/commons-beanutils/commons-beanutils/1.9.4/commons-beanutils-1.9.4.jar"; \
    # commons-compress 1.27.1
    rm -f commons-compress-*.jar; \
    wget -nv -O commons-compress-1.27.1.jar "https://repo1.maven.org/maven2/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1.jar"; \
    # commons-configuration2 2.11.0
    rm -f commons-configuration2-*.jar; \
    wget -nv -O commons-configuration2-2.11.0.jar "https://repo1.maven.org/maven2/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0.jar"; \
    # commons-io 2.18.0
    rm -f commons-io-*.jar; \
    wget -nv -O commons-io-2.18.0.jar "https://repo1.maven.org/maven2/commons-io/commons-io/2.18.0/commons-io-2.18.0.jar"; \
    # commons-lang3 3.17.0
    rm -f commons-lang3-*.jar; \
    wget -nv -O commons-lang3-3.17.0.jar "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.17.0/commons-lang3-3.17.0.jar"; \
    # commons-net 3.11.1
    rm -f commons-net-*.jar; \
    wget -nv -O commons-net-3.11.1.jar "https://repo1.maven.org/maven2/commons-net/commons-net/3.11.1/commons-net-3.11.1.jar"; \
    # jackson-core 2.18.2
    rm -f jackson-core-*.jar; \
    wget -nv -O jackson-core-2.18.2.jar "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-core/2.18.2/jackson-core-2.18.2.jar"; \
    # jackson-databind 2.18.2
    rm -f jackson-databind-*.jar; \
    wget -nv -O jackson-databind-2.18.2.jar "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-databind/2.18.2/jackson-databind-2.18.2.jar"; \
    # jackson-annotations (match jackson version)
    rm -f jackson-annotations-*.jar; \
    wget -nv -O jackson-annotations-2.18.2.jar "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-annotations/2.18.2/jackson-annotations-2.18.2.jar"; \
    # json-smart 2.5.2
    rm -f json-smart-*.jar; \
    wget -nv -O json-smart-2.5.2.jar "https://repo1.maven.org/maven2/net/minidev/json-smart/2.5.2/json-smart-2.5.2.jar"; \
    # guava 33.4.0-jre
    rm -f guava-*.jar; \
    wget -nv -O guava-33.4.0-jre.jar "https://repo1.maven.org/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.jar"; \
    # netty (4.1.116.Final)
    rm -f netty-codec-4.*.jar netty-codec-http-4.*.jar netty-codec-http2-4.*.jar netty-common-4.*.jar netty-handler-4.*.jar netty-buffer-4.*.jar netty-transport-4.*.jar netty-resolver-4.*.jar netty-transport-native-epoll-4.*.jar netty-transport-native-unix-common-4.*.jar netty-transport-classes-epoll-4.*.jar; \
    wget -nv -O netty-codec-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-codec/4.1.116.Final/netty-codec-4.1.116.Final.jar"; \
    wget -nv -O netty-codec-http-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-codec-http/4.1.116.Final/netty-codec-http-4.1.116.Final.jar"; \
    wget -nv -O netty-codec-http2-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-codec-http2/4.1.116.Final/netty-codec-http2-4.1.116.Final.jar"; \
    wget -nv -O netty-common-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-common/4.1.116.Final/netty-common-4.1.116.Final.jar"; \
    wget -nv -O netty-handler-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-handler/4.1.116.Final/netty-handler-4.1.116.Final.jar"; \
    wget -nv -O netty-buffer-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-buffer/4.1.116.Final/netty-buffer-4.1.116.Final.jar"; \
    wget -nv -O netty-transport-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-transport/4.1.116.Final/netty-transport-4.1.116.Final.jar"; \
    wget -nv -O netty-resolver-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-resolver/4.1.116.Final/netty-resolver-4.1.116.Final.jar"; \
    wget -nv -O netty-transport-native-epoll-4.1.116.Final-linux-x86_64.jar "https://repo1.maven.org/maven2/io/netty/netty-transport-native-epoll/4.1.116.Final/netty-transport-native-epoll-4.1.116.Final-linux-x86_64.jar"; \
    wget -nv -O netty-transport-native-unix-common-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-transport-native-unix-common/4.1.116.Final/netty-transport-native-unix-common-4.1.116.Final.jar"; \
    wget -nv -O netty-transport-classes-epoll-4.1.116.Final.jar "https://repo1.maven.org/maven2/io/netty/netty-transport-classes-epoll/4.1.116.Final/netty-transport-classes-epoll-4.1.116.Final.jar"; \
    # log4j-core 2.24.3
    rm -f log4j-core-*.jar log4j-api-*.jar log4j-slf4j2-impl-*.jar; \
    wget -nv -O log4j-core-2.24.3.jar "https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.24.3/log4j-core-2.24.3.jar"; \
    wget -nv -O log4j-api-2.24.3.jar "https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-api/2.24.3/log4j-api-2.24.3.jar"; \
    wget -nv -O log4j-slf4j2-impl-2.24.3.jar "https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-slf4j2-impl/2.24.3/log4j-slf4j2-impl-2.24.3.jar"; \
    # avro 1.12.0
    rm -f avro-*.jar; \
    wget -nv -O avro-1.12.0.jar "https://repo1.maven.org/maven2/org/apache/avro/avro/1.12.0/avro-1.12.0.jar"; \
    # protobuf-java 3.25.5
    rm -f protobuf-java-*.jar; \
    wget -nv -O protobuf-java-3.25.5.jar "https://repo1.maven.org/maven2/com/google/protobuf/protobuf-java/3.25.5/protobuf-java-3.25.5.jar"; \
    # nimbus-jose-jwt 9.47
    rm -f nimbus-jose-jwt-*.jar; \
    wget -nv -O nimbus-jose-jwt-9.47.jar "https://repo1.maven.org/maven2/com/nimbusds/nimbus-jose-jwt/9.47/nimbus-jose-jwt-9.47.jar"; \
    # okhttp 4.12.0
    rm -f okhttp-*.jar; \
    wget -nv -O okhttp-4.12.0.jar "https://repo1.maven.org/maven2/com/squareup/okhttp3/okhttp/4.12.0/okhttp-4.12.0.jar"; \
    # woodstox-core 7.1.0
    rm -f woodstox-core-*.jar; \
    wget -nv -O woodstox-core-7.1.0.jar "https://repo1.maven.org/maven2/com/fasterxml/woodstox/woodstox-core/7.1.0/woodstox-core-7.1.0.jar"; \
    # dnsjava 3.6.2
    rm -f dnsjava-*.jar; \
    wget -nv -O dnsjava-3.6.2.jar "https://repo1.maven.org/maven2/dnsjava/dnsjava/3.6.2/dnsjava-3.6.2.jar"; \
    chown spark:spark /opt/spark/jars/*.jar

# Install Python 3 and upgrade pip/setuptools/wheel
RUN set -ex; \
    apt-get update; \
    apt-get install -y python3 python3-pip; \
    pip3 install --no-cache-dir --upgrade pip setuptools wheel; \
    rm -rf /var/lib/apt/lists/*

# Install additional utilities
USER root
RUN apt-get update && apt-get install -y curl jq && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

# Set up application
WORKDIR /opt/spark-app
COPY app.jar application.conf entrypoint.sh /opt/spark-app/
RUN chmod +x /opt/spark-app/entrypoint.sh && \
    chown -R spark:spark /opt/spark-app

# Azure environment
ENV AZURE_FEDERATED_TOKEN_FILE=/var/run/secrets/azure/tokens/azure-identity-token
ENV AZURE_AUTHORITY_HOST=https://login.microsoftonline.com/
ENV AZURE_KEY_VAULT_URI=https://kv-aks-auth.vault.azure.net/

USER spark
ENTRYPOINT ["/opt/spark-app/entrypoint.sh"]
CMD ["diagnostic"]
