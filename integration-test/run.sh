#!/bin/bash
set -ex

source extra.sh

echo "Required variable check"
if [ -z "$CONTAINER_PREFIX" ]; then
  echo "You must set the shell env variable CONTAINER_PREFIX so we can push the containers to the correct place"
  exit 1
fi
# Sort of required, we can set is kubectl cluster-info works
if [ -z "$K8S_ENDPOINT" ]; then
  echo "You should configure your K8S_ENDPOINT, see kubectl cluster-info"
  exit 1
fi

echo "Required command check"
if ! command -v helm &> /dev/null
then
  echo "Helm not found, please install helm https://helm.sh/docs/intro/install/"
  exit 1
fi
echo "Configuring command for downloads"


echo "Configuring default variables if unset"
INTEGRATION_RUN_DIR=${INTEGRATION_RUN_DIR:-$(mktemp -d -t iceberg-int-XXXXXXXXXX)}
# Repos and branches to test
SPARK_REPO=${SPARK_REPO:-"https://github.com/holdenk/spark"}
SPARK_BRANCHES=${SPARK_BRANCHES:-"master future"}
SPARK_BRANCHES_ARRAY=($(echo ${SPARK_BRANCHES} | tr " " "\n"))
SPARK_VERSION=${SPARK_VERSION:-3.1.1}
SPARK_SUBDIR=${SPARK_SUBDIR:-spark-${SPARK_VERSION}-bin-hadoop3.2}
SPARK_HOME=${SPARK_HOME:-"${INTEGRATION_RUN_DIR}/${SPARK_SUBDIR}"}
SPARK_ARCHIVE=${SPARK_ARCHIVE:-${SPARK_SUBDIR}.tgz}
FLINK_VERSION=${FLINK_VERSION:-1.11}
# Storage
MINIO_REPO=${MINIO_REPO:-minio/minio}
MINIO_TAG=${MINIO_TAG:-RELEASE.2021-02-07T01-31-02Z}
MINIO_MC_REPO=${MINIO_MC_REPO:-minio/mc}
MINIO_MC_TAG=${MINIO_MC_TAG:-RELEASE.2021-02-07T02-02-05Z}
# K8s
if [ -z "${TEST_NS}" ]; then
  export TEST_NS=iceberg-integration
  kubectl get namespace "${TEST_NS}" || kubectl create namespace "${TEST_NS}"
fi
kubectl config set-context --current --namespace="${TEST_NS}"
# Apply any extra configuration (e.g. networking, etc.)
if [ -f extra.yaml ]; then
  cat extra.yaml | sed 's@TEST_NS@'"$TEST_NS"'@' | kubectl apply -f -
fi
if [ -z "$SERVICE_ACCOUNT" ]; then
  echo "No service account configured, making one"
  kubectl get serviceaccount spark-iceberg || kubectl create serviceaccount spark-iceberg --namespace ${TEST_NS}
  export SERVICE_ACCOUNT=spark-iceberg
  kubectl get rolebinding spark-ice-role || kubectl create rolebinding spark-ice-role --clusterrole=edit --serviceaccount="${TEST_NS}:${SERVICE_ACCOUNT}" --namespace=${TEST_NS}
fi
TAG=${TAG:-$(date +%s)}
# Archs to build for, e.g. "--platform linux/amd64,linux/arm64"
#ARCHS=${ARCHS:""}

#TODO: Add multi-arch
#ARCHS=${ARCHS:-"--platform linux/amd64,linux/arm64"}

echo "Initial setup"
INTEGRATION_DIR=$(dirname "$0")
cd "${INTEGRATION_DIR}"
INTEGRATION_DIR=$(pwd)
cd ..
ICEBERG_DIR=$(pwd)
#./gradlew build


echo "Building the base containers"
pushd "${INTEGRATION_RUN_DIR}"

# Build the base Spark container
if [ ! -d "${SPARK_HOME}" ]; then
  if [ ! -f "${SPARK_ARCHIVE}" ]; then
    (wget "https://www.apache.org/dyn/closer.cgi?action=download&filename=spark/spark-${SPARK_VERSION}/${SPARK_ARCHIVE}" -O ${SPARK_ARCHIVE} || wget "https://downloads.apache.org/spark/spark-${SPARK_VERSION}/${SPARK_ARCHIVE}")
  fi
  tar -xvf "${SPARK_ARCHIVE}"
fi
pushd "${SPARK_HOME}"
# Add Bouncy Castle for K3s
if [ ! -f ./jars/bcprov-ext-jdk15on-1.68.jar ]; then
  wget https://repo1.maven.org/maven2/org/bouncycastle/bcprov-ext-jdk15on/1.68/bcprov-ext-jdk15on-1.68.jar -O ./jars/bcprov-ext-jdk15on-1.68.jar
fi
unset SPARK_TAGS
SPARK_TAGS=("${TAG}-release-${SPARK_VERSION}")
SPARK_HASHES=("release-${SPARK_VERSION}")
./bin/docker-image-tool.sh -r "${CONTAINER_PREFIX}" -t "${TAG}-release-${SPARK_VERSION}" -b java_image_tag=11-jre-slim -X  -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build || (./bin/docker-image-tool.sh -r "${CONTAINER_PREFIX}" -t "${TAG}-release-${SPARK_VERSION}" -b java_image_tag=11-jre-slim   -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build && ./bin/docker-image-tool.sh -r "${CONTAINER_PREFIX}" -t "${TAG}-release-${SPARK_VERSION}" -b java_image_tag=11-jre-slim   -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile push)
popd

# Build the variants
unset idx
if [ ! -d spark ]; then
  git clone "${SPARK_REPO}"
fi


for branch in "${SPARK_BRANCHES_ARRAY[@]}"
do
  # Copy so we don't have to clean build everytime if we're recycling the run dir.
  if [ ! -d "spark-${branch}" ]; then
    cp -af spark "spark-${branch}"
  fi
  pushd "spark-${branch}"
  (git checkout "${branch}" && \
   git pull && \
#   ./build/mvn -Pkubernetes -Phadoop-aws compile package -DskipTests && \
  (./bin/docker-image-tool.sh -r "${CONTAINER_PREFIX}" -t "${TAG}-${branch}" -b java_image_tag=11-jre-slim -X -p resource-managers/kubernetes/docker/src/main/dockerfiles/spark/bindings/python/Dockerfile build || ( \
   ./bin/docker-image-tool.sh -r "${CONTAINER_PREFIX}" -t "${TAG}-${branch}" -b java_image_tag=11-jre-slim  -p resource-managers/kubernetes/docker/src/main/dockerfiles/spark/bindings/python/Dockerfile build && \
   ./bin/docker-image-tool.sh -r "${CONTAINER_PREFIX}" -t "${TAG}-${branch}" push)) && \
  SPARK_TAGS+=("${TAG}-${branch}") \
  SPARK_HASHES+=("$(git rev-parse HEAD)") \
  ) || echo "Spark branch ${branch} failed at $(git log -n 1)"
  popd
done

if [ ! -d flink-docker ]; then
  git clone git@github.com:apache/flink-docker.git
fi
pushd "flink-docker/${FLINK_VERSION}/scala_2.12-java11-debian"
(docker buildx build . -t "${CONTAINER_PREFIX}/flink:${TAG}" --push ${DOCKER_EXTRA} || docker build . -t "${CONTAINER_PREFIX}/flink:${TAG}")
popd

echo "Building support tools (TPCDS, etc.)"
pushd "${INTEGRATION_RUN_DIR}"
if [ ! -d spark-tpcds-datagen ]; then
  git clone git@github.com:maropu/spark-tpcds-datagen.git
fi
pushd spark-tpcds-datagen
if [ ! -f ./target/spark-tpcds-datagen_2.12-0.1.0-SNAPSHOT-with-dependencies.jar ]; then
  ./build/mvn package -DskipTests
fi
popd

if [ ! -d trino-on-k8s ]; then
  git clone git@github.com:joshuarobinson/trino-on-k8s.git
fi
pushd trino-on-k8s/hive_metastore
docker build -t "${CONTAINER_PREFIX}/hivemetastore:latest" .
docker push "${CONTAINER_PREFIX}/hivemetastore:latest"
popd


echo "Build the containers with Iceberg & tools present"
if [ ! -d iceberg ]; then
  cp -af ${ICEBERG_DIR} ./iceberg
fi
  
for SPARK_TAG in "${SPARK_TAGS[@]}"
do
  docker buildx build . -f "${INTEGRATION_DIR}/containers/spark/Dockerfile" -t "${CONTAINER_PREFIX}/iceberg-spark:${SPARK_TAG}" --build-arg base="${CONTAINER_PREFIX}/spark-py:${SPARK_TAG}" --push ${DOCKER_EXTRA}
done

docker buildx build . -f "${INTEGRATION_DIR}/containers/flink/Dockerfile" -t "${CONTAINER_PREFIX}/iceberg-flink:${TAG}" --build-arg base="${CONTAINER_PREFIX}/flink:${TAG}" --push ${DOCKER_EXTRA}

popd

if [ "$SKIP_MINIO" != "true" ]; then
  echo "Deploy minio"
  helm repo add minio https://helm.min.io/
  helm repo update
  deployment=minio-iceberg-part
  helm status --namespace "${TEST_NS}" "${deployment}" || helm install --namespace "${TEST_NS}"  --set accessKey=myaccesskey,secretKey=mysecretkey --set image.repository="${MINIO_REPO}" --set image.tag="${MINIO_TAG}" --set defaultBucket.enabled=true  --set persistence.enabled=false --set resources.requests.memory=10Gi --set resources.limits.memory=12Gi --set podLabels."sdr\.appname"="minio" "${deployment}" minio/minio
  export S3_ACCESS_KEY=myaccesskey
  export S3_SECRET_KEY=mysecretkey
  export S3_ENDPOINT="${deployment}.${TEST_NS}.svc:9000"
  export S3_ROOT="s3a://bucket"
fi

echo "Deploying hive metastore"
echo "Deploying hive metastore config map"
pushd "${INTEGRATION_RUN_DIR}/trino-on-k8s/hive_metastore"
kubectl create configmap metastore-cfg --dry-run --from-file=metastore-site.xml --from-file=core-site.xml -o yaml | kubectl apply -f -
popd

cat ${INTEGRATION_DIR}/metastore.yaml | sed 's@CONTAINER_PREFIX@'"$CONTAINER_PREFIX"'@'  | kubectl apply -f -
# exit 0

# Create SPARK_CONFIG with the FS layer & K8s config
export SPARK_CONFIG="--conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem --conf spark.hadoop.fs.s3a.path.style.access=true --conf spark.hadoop.fs.s3a.access.key=${S3_ACCESS_KEY} --conf spark.hadoop.fs.s3a.secret.key=${S3_SECRET_KEY} --conf spark.hadoop.fs.s3a.endpoint=http://${S3_ENDPOINT} --master k8s://${K8S_ENDPOINT} --conf spark.kubernetes.namespace=${TEST_NS} --conf spark.kubernetes.authenticate.driver.serviceAccountName=${SERVICE_ACCOUNT} --deploy-mode cluster $USER_SPARK_CONFIG --conf spark.hadoop.javax.jdo.option.ConnectionDriverName=com.mysql.jdbc.Driver --conf spark.hadoop.javax.jdo.option.ConnectionURL=mysql-service:3306 --conf spark.hadoop.javax.jdo.option.ConnectionUserName=root --conf spark.hadoop.javax.jdo.option.ConnectionPassword=bloopTheNoop --conf spark.hadoop.metastore.warehouse.dir=${S3_ROOT}/warehouse --conf spark.hadoop.metastore.thrift.port=9083 --conf spark.sql.catalog.spark_catalog.type=hive --conf spark.executor.instances=20"
pwd
pushd ${INTEGRATION_DIR}
# We can't directly read -ax so flatten with space seperators. ugh.
export SPARK_TAGS_FLAT="${SPARK_TAGS[0]}"
for i in "${SPARK_TAGS[@]:1}"; do
   SPARK_TAGS_FLAT+=" $i"
done
export SPARK_HASHES_FLAT="${SPARK_HASHES[0]}"
for i in "${SPARK_HASHES[@]:1}"; do
   SPARK_HASHES_FLAT+=" $i"
done
export SPARK_HOME
export SPARK_CONFIG
export SPARK_TAGS_FLAT
export
echo "Getting ready to run tests with Spark tags ${SPARK_TAGS_FLAT}"
CALLED_FROM_RUN=1 python3 run_tests.py


#echo "Cleaning up"
#rm -rf "${INTEGRATION_RUN_DIR}"
