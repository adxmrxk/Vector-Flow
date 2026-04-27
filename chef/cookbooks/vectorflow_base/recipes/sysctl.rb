#
# Cookbook:: vectorflow_base
# Recipe:: sysctl
#
# Configures kernel parameters for optimal performance
#

# Apply sysctl settings
node['vectorflow']['base']['sysctl'].each do |key, value|
  sysctl key do
    value value
    action :apply
  end
end

# Ensure sysctl configuration persists
template '/etc/sysctl.d/99-vectorflow.conf' do
  source 'sysctl.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(sysctl_settings: node['vectorflow']['base']['sysctl'])
  notifies :run, 'execute[reload-sysctl]', :immediately
end

execute 'reload-sysctl' do
  command 'sysctl --system'
  action :nothing
end

log 'sysctl_complete' do
  message 'VectorFlow sysctl settings applied successfully'
  level :info
end
