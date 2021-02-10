#!/bin/bash
set -ex

echo "Required variable check"
if [ -z "$CONTAINER_PREFIX" ]; then
  echo "You must set the shell env variable CONTAINER_PREFIX so we can push the containers to the correct place"
  exit 1
fi

echo "Configuring default variables if unset"
INTEGRATION_RUN_DIR=${INTEGRATION_RUN_DIR:-$(mktemp -d -t iceberg-int-XXXXXXXXXX)}
SPARK_VERSION=${SPARK_VERSION:-3.0.1}
SPARK_DIR=${SPARK_DIR:-spark-${SPARK_VERSION}-bin-hadoop2.7}
SPARK_ARCHIVE=${SPARK_ARCHIVE:-${SPARK_DIR}.tgz}
FLINK_VERSION=${FLINK_VERSION:-1.11}
TAG=$(date +%s)

echo "Configuring command for downloads"
DL="axel"
if ! command -v axel &> /dev/null
then
  DL="wget"
fi
#TODO: Add multi-arch
#ARCHS=${ARCHS:-"--platform linux/amd64,linux/arm64"}

echo "Initial setup"
INTEGRATION_DIR=$(dirname "$0")
cd "${INTEGRATION_DIR}"
cd ..
ICEBERG_DIR=$(pwd)
#./gradlew build


echo "Building the base containers"
pushd "${INTEGRATION_RUN_DIR}"
if [ ! -d "${SPARK_DIR}" ]; then
  if [ ! -f "${SPARK_ARCHIVE}" ]; then
    (${DL} "https://mirrors.ocf.berkeley.edu/apache/spark/spark-${SPARK_VERSION}/${SPARK_ARCHIVE}" || ${DL} "https://downloads.apache.org/spark/spark-${SPARK_VERSION}/${SPARK_ARCHIVE}")
  fi
  tar -xvf "${SPARK_ARCHIVE}"
fi
pushd "${SPARK_DIR}"
./bin/docker-image-tool.sh -r "${CONTAINER_PREFIX}" -t "${TAG}" -b java_image_tag=11-jre-slim  -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build
popd
if [ ! -d flink-docker ]; then
  git clone git@github.com:apache/flink-docker.git
fi
pushd "flink-docker/${FLINK_VERSION}/scala_2.12-java11-debian"
docker build . -t "${CONTAINER_PREFIX}/flink:${TAG}"
popd


echo "Cleaning up"
rm -rf "${INTEGRATION_RUN_DIR}"
