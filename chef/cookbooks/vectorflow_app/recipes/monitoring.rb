#
# Cookbook:: vectorflow_app
# Recipe:: monitoring
#
# Sets up monitoring for VectorFlow services
#

# Create monitoring directory
directory "#{node['vectorflow']['base']['log_dir']}/monitoring" do
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0755'
end

# Generate Prometheus scrape config
template "#{node['vectorflow']['base']['config_dir']}/prometheus-targets.yaml" do
  source 'prometheus-targets.yaml.erb'
  owner 'root'
  group node['vectorflow']['base']['group']
  mode '0640'
  variables(services: node['vectorflow']['app']['services'])
end

# Create health check script
template '/usr/local/bin/vectorflow-health-check' do
  source 'health-check.sh.erb'
  owner 'root'
  group 'root'
  mode '0755'
  variables(
    services: node['vectorflow']['app']['services'],
    health_check: node['vectorflow']['app']['health_check']
  )
end

# Schedule health checks
cron 'vectorflow-health-check' do
  minute '*/5'
  command '/usr/local/bin/vectorflow-health-check >> /var/log/vectorflow/monitoring/health.log 2>&1'
  user 'root'
end

# Create service status script
template '/usr/local/bin/vectorflow-status' do
  source 'status.sh.erb'
  owner 'root'
  group 'root'
  mode '0755'
end

log 'monitoring_complete' do
  message 'VectorFlow monitoring configured successfully'
  level :info
end
