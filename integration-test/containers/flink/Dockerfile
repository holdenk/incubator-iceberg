ARG base
FROM ${base}
COPY iceberg/flink-runtime/build/libs/* /opt/flink/lib/
ADD https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.2.0/hadoop-aws-3.2.0.jar /opt/spark/jars/
ADD https://repo1.maven.org/maven2/org/bouncycastle/bcprov-ext-jdk15on/1.68/bcprov-ext-jdk15on-1.68.jar /opt/spark/jars
ADD https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.563/aws-java-sdk-bundle-1.11.563.jar /opt/spark/jars/
ADD https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.49/mysql-connector-java-5.1.49.jar /opt/spark/jars/
