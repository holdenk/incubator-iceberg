import sys
import os
MIN_PYTHON = (3,8)

# Check that things are ok.
if sys.version_info < MIN_PYTHON:
    sys.exit("Python %s.%s or later is required.\n" % MIN_PYTHON)

print(os.environ)

if "CALLED_FROM_RUN" not in os.environ:
    sys.exit("Please use run.sh to call me, thanks!")

def generate_data(scale_factors):
    for factor in scale_factors:
        classname = "org.apache.spark.sql.execution.benchmark.TPCDSDatagen"
        target = s3_root + "/" + str(factor)
        jobname="dsgen" + str(factor)
        tag = spark_tags[0]
        image=f"{container_prefix}/iceberg-spark:{tag}"
        app_name = f"spark-tpcds-test-gen-{factor}"
        jar="local:///spark-tpcds-datagen_2.12-0.1.0-SNAPSHOT-with-dependencies.jar"
        exec_str = f"{spark_home}/bin/spark-submit --conf spark.kubernetes.container.image={image}   --class {classname} --name {app_name} --conf spark.kubernetes.driver.label.sdr.appname=spark --conf spark.sql.catalog.hive_prod=org.apache.iceberg.spark.SparkCatalog --conf spark.kubernetes.executor.label.sdr.appname=spark {spark_config} {jar} --output-location {target} --scale-factor {factor}"
        ret = os.system(exec_str)
        if ret != 0:
            sys.exit(f"Non zero exit while running {exec_str} generating data, k bye!")




container_prefix = os.getenv("CONTAINER_PREFIX")
spark_tags = os.getenv("SPARK_TAGS_FLAT").split(" ")
spark_home = os.getenv("SPARK_HOME")
spark_config = os.getenv("SPARK_CONFIG")
s3_root = os.getenv("S3_ROOT")
scale_factors = [1, 2, 3]
generate_data(scale_factors)
