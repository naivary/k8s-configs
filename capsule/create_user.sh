#!/bin/bash
set -e

USER_NAME="$1"
GROUP="$2"

# $1 = cmd name
function check_cmd() {
    local cmd=$1

    if ! hash $cmd 2>/dev/null; then
        echo "Error: ${cmd} not found"
        exit 1
    fi
}

function info() {
    local msg="$1"
    echo "[*] ${msg}"
}

if [ -z "${USER_NAME}" ]; then
    echo "Missing username as the first argument"
    exit 1
fi

if [ -z "${GROUP}" ]; then
  echo "Missing group as second argument"
  exit 1
fi

check_cmd openssl
check_cmd kubectl

CSR_NAME="${USER_NAME}-csr"
KUBECONFIG_FILE="${USER_NAME}.kubeconfig"

info "Generating private key and CSR for user: $USER_NAME"
openssl genrsa -out ${USER_NAME}.key 2048
openssl req -new -key ${USER_NAME}.key -out ${USER_NAME}.csr -subj "/CN=${USER_NAME}/O=${GROUP}"

CSR_BASE64=$(base64 ${USER_NAME}.csr | tr -d '\n')

info "Delete existing CSR from previous runs"
kubectl delete csr "${CSR_NAME}" --ignore-not-found

info "Create CSR-Request"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  groups:
  - system:authenticated
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

info "Approving CSR"
kubectl certificate approve ${CSR_NAME}

info "Fetching signed certificate"
kubectl get csr ${CSR_NAME} -o jsonpath='{.status.certificate}' \
  | base64 --decode > ${USER_NAME}.crt

info "Gathering cluster info"
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

#CLUSTER_CA_DECODED=$(echo "${CLUSTER_CA}" | base64 -d)

info "Creating kubeconfig for user: $USER_NAME"
kubectl config set-cluster ${CLUSTER_NAME} \
  --server=${CLUSTER_SERVER} \
  --certificate-authority-data="${CLUSTER_CA}" \
  --kubeconfig=${KUBECONFIG_FILE} > /dev/null

kubectl config set-credentials ${USER_NAME} \
  --client-certificate=${USER_NAME}.crt \
  --client-key=${USER_NAME}.key \
  --kubeconfig=${KUBECONFIG_FILE} > /dev/null

kubectl config set-context ${USER_NAME}-context \
  --cluster=${CLUSTER_NAME} \
  --user=${USER_NAME} \
  --kubeconfig=${KUBECONFIG_FILE} > /dev/null

kubectl config use-context ${USER_NAME}-context --kubeconfig=${KUBECONFIG_FILE} > /dev/null

echo "[✔] Kubeconfig generated: ${KUBECONFIG_FILE}"
