#
# Cookbook:: vectorflow_security
# Recipe:: audit
#
# Configures auditd for security auditing
#

return unless node['vectorflow']['security']['auditd']['enabled']

audit_config = node['vectorflow']['security']['auditd']

# Ensure auditd is installed
package 'auditd' do
  action :install
end

# Configure auditd
template '/etc/audit/auditd.conf' do
  source 'auditd.conf.erb'
  owner 'root'
  group 'root'
  mode '0640'
  variables(
    log_file: audit_config['log_file'],
    max_log_file: audit_config['max_log_file'],
    num_logs: audit_config['num_logs']
  )
  notifies :restart, 'service[auditd]', :delayed
end

# Add VectorFlow-specific audit rules
template '/etc/audit/rules.d/vectorflow.rules' do
  source 'vectorflow-audit.rules.erb'
  owner 'root'
  group 'root'
  mode '0640'
  notifies :run, 'execute[reload-audit-rules]', :delayed
end

execute 'reload-audit-rules' do
  command 'augenrules --load'
  action :nothing
end

# Enable and start auditd
service 'auditd' do
  action [:enable, :start]
end

log 'auditd_complete' do
  message 'Audit logging configured successfully'
  level :info
end
