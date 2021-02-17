ARG base
FROM ${base}
COPY iceberg/spark3-runtime/build/libs/* /opt/spark/jars/
COPY spark-tpcds-datagen/target/spark-tpcds-datagen_2.12-0.1.0-SNAPSHOT-with-dependencies.jar /