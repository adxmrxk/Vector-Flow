# =================================
# VectorFlow Worker Policy
# =================================
# This policy configures a VectorFlow worker node
# with Docker, Kubernetes, and the application
#
# Usage:
#   chef install policies/vectorflow-worker.rb
#   chef push production policies/vectorflow-worker.rb

name 'vectorflow-worker'
default_source :supermarket

run_list [
  'vectorflow_base::default',
  'vectorflow_docker::default',
  'vectorflow_kubernetes::default',
  'vectorflow_security::default',
  'vectorflow_app::default',
]

# Local cookbook paths
cookbook 'vectorflow_base', path: '../cookbooks/vectorflow_base'
cookbook 'vectorflow_docker', path: '../cookbooks/vectorflow_docker'
cookbook 'vectorflow_kubernetes', path: '../cookbooks/vectorflow_kubernetes'
cookbook 'vectorflow_security', path: '../cookbooks/vectorflow_security'
cookbook 'vectorflow_app', path: '../cookbooks/vectorflow_app'

# External dependencies
cookbook 'apt', '~> 7.0'
cookbook 'yum', '~> 7.0'
cookbook 'ntp', '~> 5.0'

# Worker-specific configuration
default['vectorflow']['kubernetes']['node_type'] = 'worker'
default['vectorflow']['app']['services']['inference']['replicas'] = 3
