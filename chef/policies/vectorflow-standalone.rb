# =================================
# VectorFlow Standalone Policy
# =================================
# This policy configures a standalone VectorFlow
# development environment with Minikube
#
# Usage:
#   chef install policies/vectorflow-standalone.rb
#   chef push development policies/vectorflow-standalone.rb

name 'vectorflow-standalone'
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

# Standalone configuration (Minikube)
default['vectorflow']['kubernetes']['node_type'] = 'standalone'
default['vectorflow']['kubernetes']['minikube']['cpus'] = 4
default['vectorflow']['kubernetes']['minikube']['memory'] = '8192'

# Reduced replicas for local development
default['vectorflow']['app']['services']['gateway']['replicas'] = 1
default['vectorflow']['app']['services']['worker']['replicas'] = 1
default['vectorflow']['app']['services']['inference']['replicas'] = 1
default['vectorflow']['app']['services']['frontend']['replicas'] = 1

# Relaxed security for development
default['vectorflow']['security']['firewall']['enabled'] = false
default['vectorflow']['security']['fail2ban']['enabled'] = false
