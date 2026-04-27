# =================================
# VectorFlow Docker Attributes
# =================================

# Docker version (leave empty for latest)
default['vectorflow']['docker']['version'] = ''

# Docker daemon configuration
default['vectorflow']['docker']['daemon'] = {
  'log-driver' => 'json-file',
  'log-opts' => {
    'max-size' => '100m',
    'max-file' => '5',
  },
  'storage-driver' => 'overlay2',
  'live-restore' => true,
  'userland-proxy' => false,
  'default-ulimits' => {
    'nofile' => {
      'Name' => 'nofile',
      'Hard' => 65536,
      'Soft' => 65536,
    },
  },
  'metrics-addr' => '0.0.0.0:9323',
  'experimental' => false,
}

# Docker Compose version
default['vectorflow']['docker']['compose_version'] = '2.24.0'

# Container runtime settings
default['vectorflow']['docker']['default_runtime'] = 'runc'

# Docker network settings
default['vectorflow']['docker']['networks'] = {
  'vectorflow-net' => {
    'driver' => 'bridge',
    'subnet' => '172.28.0.0/16',
  },
}

# Cleanup settings
default['vectorflow']['docker']['prune_schedule'] = 'weekly'
default['vectorflow']['docker']['prune_keep_images'] = 10

# Registry configuration
default['vectorflow']['docker']['registries'] = []
default['vectorflow']['docker']['insecure_registries'] = ['localhost:5000']
