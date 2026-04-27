#
# Cookbook:: vectorflow_security
# Recipe:: fail2ban
#
# Configures fail2ban for intrusion prevention
#

return unless node['vectorflow']['security']['fail2ban']['enabled']

fail2ban_config = node['vectorflow']['security']['fail2ban']

# Ensure fail2ban is installed
package 'fail2ban' do
  action :install
end

# Configure fail2ban
template '/etc/fail2ban/jail.local' do
  source 'jail.local.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    bantime: fail2ban_config['bantime'],
    findtime: fail2ban_config['findtime'],
    maxretry: fail2ban_config['maxretry']
  )
  notifies :restart, 'service[fail2ban]', :delayed
end

# Create VectorFlow-specific jail
template '/etc/fail2ban/jail.d/vectorflow.conf' do
  source 'vectorflow-jail.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :restart, 'service[fail2ban]', :delayed
end

# Enable and start fail2ban
service 'fail2ban' do
  action [:enable, :start]
end

log 'fail2ban_complete' do
  message 'Fail2ban configured successfully'
  level :info
end
