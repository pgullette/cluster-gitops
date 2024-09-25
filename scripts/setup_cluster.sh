# File that contains the age key
set -e
CLUSTER_NAME=$1
GITOPS_USERNAME=gitops
GITOPS_BRANCH=$2
K8S_RESOURCES=""

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

# Generate bootstrap ns and rbac
K8S_RESOURCES=$(\
    ytt --ignore-unknown-comments -f ../kapp/globals/values \
        -f ../kapp/globals/templates/bootstrap/bootstrap-ns.yaml \
        -f ../kapp/globals/templates/bootstrap/bootstrap-rbac.yaml \
)

# Generate age-key secret
K8S_RESOURCES+="\n---\n"$(\
    kubectl create secret -n cluster-gitops generic age-key \
        --from-file key.txt=${AGE_KEY} \
        -o yaml --dry-run=client \
)

# Generate gitops credential
K8S_RESOURCES+="\n---\n"$(\
    kubectl create secret -n cluster-gitops generic cluster-gitops-creds \
        --from-literal username=gitops \
        --from-file password=${GITOPS_TOKEN} \
        -o yaml --dry-run=client \
)

# Generate cluster data values configmap
cluster_gitops_values=$(cat <<EOF
cluster_name: $CLUSTER_NAME
gitops_branch: $GITOPS_BRANCH
EOF
)

K8S_RESOURCES+="\n---\n"$(\
    kubectl create configmap -n cluster-gitops cluster-gitops-values \
        --from-literal cluster-gitops-values.yaml="${cluster_gitops_values}" \
        -o yaml --dry-run=client \
)

# Generate bootstrap app to start gitops process
K8S_RESOURCES+="\n---\n"$(\
    ytt --ignore-unknown-comments -f ../kapp/globals/values \
        -f ../kapp/globals/templates/bootstrap/bootstrap-app.yaml \
)

# echo "${K8S_RESOURCES}" > k8s-resources.yaml

# Apply the generated k8s resources as a single kapp app
echo "${K8S_RESOURCES}" | kapp deploy -a cluster-gitops-bootstrap-resources -y -f -

# Delete temp dir
# rm -rf ${TMP_DIR}