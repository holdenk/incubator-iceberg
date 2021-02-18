ARG base
FROM ${base}
COPY iceberg/spark3-runtime/build/libs/* /opt/spark/jars/
ADD https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.2.2/hadoop-aws-3.2.2.jar /opt/spark/jars/
ADD https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.563/aws-java-sdk-bundle-1.11.563.jar /opt/spark/jars/
COPY spark-tpcds-datagen/target/spark-tpcds-datagen_2.12-0.1.0-SNAPSHOT-with-dependencies.jar /
USER 0
RUN chmod a+rx /opt/spark/jars/*.jar /*.jar
USER ${spark_uid}