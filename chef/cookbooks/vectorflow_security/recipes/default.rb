#
# Cookbook:: vectorflow_security
# Recipe:: default
#
# Copyright:: 2024, VectorFlow Team
# License:: MIT
#
# Security hardening for VectorFlow servers
#

include_recipe 'vectorflow_security::packages'
include_recipe 'vectorflow_security::ssh'
include_recipe 'vectorflow_security::firewall'
include_recipe 'vectorflow_security::fail2ban'
include_recipe 'vectorflow_security::audit'
include_recipe 'vectorflow_security::auto_updates'
include_recipe 'vectorflow_security::compliance_check'
