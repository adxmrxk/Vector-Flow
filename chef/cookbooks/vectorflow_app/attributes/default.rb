# =================================
# VectorFlow Application Attributes
# =================================

# Application version
default['vectorflow']['app']['version'] = 'latest'

# Container registry
default['vectorflow']['app']['registry'] = 'localhost:5000'

# Service configuration
default['vectorflow']['app']['services'] = {
  'gateway' => {
    'enabled' => true,
    'port' => 8080,
    'replicas' => 2,
    'image' => 'vectorflow-gateway',
  },
  'worker' => {
    'enabled' => true,
    'port' => 8081,
    'replicas' => 3,
    'image' => 'vectorflow-worker',
  },
  'inference' => {
    'enabled' => true,
    'port' => 8082,
    'replicas' => 2,
    'image' => 'vectorflow-inference',
  },
  'frontend' => {
    'enabled' => true,
    'port' => 3000,
    'replicas' => 2,
    'image' => 'vectorflow-frontend',
  },
}

# Model configuration
default['vectorflow']['app']['model'] = {
  'name' => 'sentence-transformers/all-MiniLM-L6-v2',
  'cache_dir' => '/var/lib/vectorflow/models',
  'batch_size' => 32,
  'max_sequence_length' => 512,
}

# Pinecone configuration
default['vectorflow']['app']['pinecone'] = {
  'environment' => 'us-east-1',
  'index_name' => 'vectorflow-index',
}

# Logging configuration
default['vectorflow']['app']['logging'] = {
  'level' => 'info',
  'format' => 'json',
  'output' => '/var/log/vectorflow',
}

# Health check configuration
default['vectorflow']['app']['health_check'] = {
  'interval' => 30,
  'timeout' => 10,
  'retries' => 3,
}

# Resource limits
default['vectorflow']['app']['resources'] = {
  'gateway' => {
    'cpu_request' => '250m',
    'cpu_limit' => '500m',
    'memory_request' => '256Mi',
    'memory_limit' => '512Mi',
  },
  'worker' => {
    'cpu_request' => '500m',
    'cpu_limit' => '1000m',
    'memory_request' => '512Mi',
    'memory_limit' => '1Gi',
  },
  'inference' => {
    'cpu_request' => '1000m',
    'cpu_limit' => '2000m',
    'memory_request' => '2Gi',
    'memory_limit' => '4Gi',
  },
  'frontend' => {
    'cpu_request' => '100m',
    'cpu_limit' => '250m',
    'memory_request' => '128Mi',
    'memory_limit' => '256Mi',
  },
}
