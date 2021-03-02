ARG base
FROM ${base}
COPY iceberg/spark3-runtime/build/libs/* /opt/spark/jars/
ADD https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.2.0/hadoop-aws-3.2.0.jar /opt/spark/jars/
ADD https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.563/aws-java-sdk-bundle-1.11.563.jar /opt/spark/jars/
ADD https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.49/mysql-connector-java-5.1.49.jar /opt/spark/jars/
COPY spark-tpcds-datagen/target/spark-tpcds-datagen_2.12-0.1.0-SNAPSHOT-with-dependencies.jar /
USER 0
RUN chmod a+rx /opt/spark/jars/*.jar /*.jar
RUN apt-get install -y inetutils-ping telnet wget
USER ${spark_uid}

# I want to debug WTF is going on with the execs.
CMD "sleep 15; /opt/entrypoint.sh; sleep 600"