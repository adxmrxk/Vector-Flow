# =================================
# VectorFlow Security Policy
# =================================
# This policy enforces security hardening
# and compliance requirements
#
# Usage:
#   chef install policies/vectorflow-security.rb
#   chef push production policies/vectorflow-security.rb

name 'vectorflow-security'
default_source :supermarket

run_list [
  'vectorflow_base::default',
  'vectorflow_security::default',
]

cookbook 'vectorflow_base', path: '../cookbooks/vectorflow_base'
cookbook 'vectorflow_security', path: '../cookbooks/vectorflow_security'

cookbook 'apt', '~> 7.0'
cookbook 'yum', '~> 7.0'
cookbook 'ntp', '~> 5.0'

# Enforce strict security settings
default['vectorflow']['security']['ssh']['permit_root_login'] = 'no'
default['vectorflow']['security']['ssh']['password_authentication'] = 'no'
default['vectorflow']['security']['ssh']['max_auth_tries'] = 3

default['vectorflow']['security']['firewall']['enabled'] = true
default['vectorflow']['security']['firewall']['default_policy'] = 'deny'

default['vectorflow']['security']['fail2ban']['enabled'] = true
default['vectorflow']['security']['fail2ban']['bantime'] = '24h'
default['vectorflow']['security']['fail2ban']['maxretry'] = 3

default['vectorflow']['security']['auditd']['enabled'] = true
default['vectorflow']['security']['auto_updates']['enabled'] = true
default['vectorflow']['security']['compliance']['cis_benchmark'] = true
