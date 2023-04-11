#!/usr/bin/env bash

ORIG_DIR="$(pwd)"
cd "$(dirname "$0")"
BIN_DIR="$(pwd)"

onExit() {
  cd "${ORIG_DIR}"
}

trap onExit EXIT

SECRET_NAME="tpzuk-azure-registry"
NAMESPACE="tpzuk"
DOCKER_SERVER="dsp3tpz.azurecr.io"

DOCKER_USERNAME="${1}"
DOCKER_PASSWORD="${2}"

secretYaml() {
  kubectl -n "${NAMESPACE}" create secret docker-registry "${SECRET_NAME}" \
  --docker-server="${DOCKER_SERVER}" \
  --docker-username="${DOCKER_USERNAME}" \
  --docker-password="${DOCKER_PASSWORD}" \
  --dry-run=client -oyaml
}

# Create Secret and then pipe to kubeseal to create the SealedSecret
secretYaml | kubeseal -o yaml --controller-name tpzuk-sealed-secrets --controller-namespace tpzuk > ss-${SECRET_NAME}.yaml
