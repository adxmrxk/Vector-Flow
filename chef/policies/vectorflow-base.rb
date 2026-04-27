# =================================
# VectorFlow Base Policy
# =================================
# This policy defines the base configuration
# that all VectorFlow servers must have
#
# Usage:
#   chef install policies/vectorflow-base.rb
#   chef push production policies/vectorflow-base.rb

name 'vectorflow-base'
default_source :supermarket

# Use stable cookbook versions
run_list 'vectorflow_base::default'

# Cookbook version constraints
cookbook 'vectorflow_base', path: '../cookbooks/vectorflow_base'
cookbook 'apt', '~> 7.0'
cookbook 'yum', '~> 7.0'
cookbook 'ntp', '~> 5.0'

# Default attributes for this policy
default['vectorflow']['base']['timezone'] = 'UTC'
default['vectorflow']['base']['packages'] = %w[
  curl
  wget
  git
  vim
  htop
  jq
  unzip
]
