# File that contains the age key
set -e
CLUSTER_NAME=$1
GITOPS_USERNAME=gitops
GITOPS_BRANCH=$2

# TMP_DIR=$(mktemp -d)

if [[ -z "${AGE_KEY}" || ! -f $AGE_KEY ]]; then
    echo "AGE_KEY needs to be set to a file containing your age key"
    exit 1
fi

if [[ -z "${GITOPS_TOKEN}" || ! -f $GITOPS_TOKEN ]]; then
    echo "GITOPS_TOKEN needs to be set to a file containing your gitops token"
    exit 1
fi

if [ -z "${CLUSTER_NAME}" ]; then
    echo "CLUSTER_NAME needs to be passed as the first argument (eg ./setup_cluster.sh CLUSTER_NAME GITOPS_BRANCH)"
    exit 1
fi

if [ -z "${GITOPS_BRANCH}" ]; then
    echo "GITOPS_BRANCH needs to be passed as the second argument (eg ./setup_cluster.sh CLUSTER_NAME GITOPS_BRANCH)"
    exit 1
fi

echo "all checks passed"
exit 0

# Create bootstrap ns and rbac
ytt --ignore-unknown-comments -f ../kapp/globals/values \
    -f ../kapp/globals/templates/bootstrap/bootstrap-ns.yaml \
    -f ../kapp/globals/templates/bootstrap/bootstrap-rbac.yaml \
    | kubectl apply -f -

# Create age-key secret
kubectl create secret -n cluster-gitops generic age-key \
    --from-file key.txt=${AGE_KEY} \
    -o yaml --dry-run=server \
    | kubectl apply -f -

# Create gitops credential
kubectl create secret -n cluster-gitops generic cluster-gitops-creds \
    --from-literal username=gitops \
    --from-file password=${GITOPS_TOKEN} \
    -o yaml --dry-run=server \
    | kubectl apply -f -

# Create cluster data values configmap
kubectl create configmap -n cluster-gitops cluster-gitops-values \
    --from-literal cluster_name=${CLUSTER_NAME} \
    --from-literal gitops_branch=${GITOPS_BRANCH} \
    -o yaml --dry-run=server \
    | kubectl apply -f -

# Apply bootstrap app to start gitops process
ytt --ignore-unknown-comments -f ../kapp/globals/values \
    -f ../kapp/globals/templates/bootstrap/bootstrap-app.yaml \
    | kubectl apply -f -

# Delete temp dir
# rm -rf ${TMP_DIR}