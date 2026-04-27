# =================================
# VectorFlow Kubernetes Attributes
# =================================

# Kubernetes version
default['vectorflow']['kubernetes']['version'] = '1.29'

# Node type: master, worker, or standalone (minikube)
default['vectorflow']['kubernetes']['node_type'] = 'standalone'

# Minikube configuration (for local development)
default['vectorflow']['kubernetes']['minikube'] = {
  'driver' => 'docker',
  'cpus' => 4,
  'memory' => '8192',
  'disk_size' => '40g',
  'kubernetes_version' => 'v1.29.0',
  'container_runtime' => 'docker',
  'addons' => %w[ingress metrics-server dashboard storage-provisioner],
}

# kubectl configuration
default['vectorflow']['kubernetes']['kubectl'] = {
  'context' => 'vectorflow',
  'namespace' => 'vectorflow',
}

# Helm configuration
default['vectorflow']['kubernetes']['helm'] = {
  'version' => '3.14.0',
  'repositories' => {
    'bitnami' => 'https://charts.bitnami.com/bitnami',
    'prometheus-community' => 'https://prometheus-community.github.io/helm-charts',
    'ingress-nginx' => 'https://kubernetes.github.io/ingress-nginx',
  },
}

# Cluster networking
default['vectorflow']['kubernetes']['network'] = {
  'pod_cidr' => '10.244.0.0/16',
  'service_cidr' => '10.96.0.0/12',
  'cni' => 'flannel',
}

# Node labels
default['vectorflow']['kubernetes']['labels'] = {
  'vectorflow.io/role' => 'worker',
  'vectorflow.io/environment' => 'production',
}

# Resource quotas
default['vectorflow']['kubernetes']['quotas'] = {
  'cpu' => '16',
  'memory' => '32Gi',
  'pods' => '50',
}
