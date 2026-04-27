#
# Cookbook:: vectorflow_docker
# Recipe:: configure
#
# Configures Docker daemon
#

# Create Docker configuration directory
directory '/etc/docker' do
  owner 'root'
  group 'root'
  mode '0755'
  action :create
end

# Configure Docker daemon
daemon_config = node['vectorflow']['docker']['daemon'].dup

# Add insecure registries if configured
if node['vectorflow']['docker']['insecure_registries'].any?
  daemon_config['insecure-registries'] = node['vectorflow']['docker']['insecure_registries']
end

file '/etc/docker/daemon.json' do
  content JSON.pretty_generate(daemon_config)
  owner 'root'
  group 'root'
  mode '0644'
  notifies :restart, 'service[docker]', :delayed
end

# Configure Docker systemd drop-in for additional settings
directory '/etc/systemd/system/docker.service.d' do
  owner 'root'
  group 'root'
  mode '0755'
  action :create
end

template '/etc/systemd/system/docker.service.d/override.conf' do
  source 'docker-override.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :run, 'execute[systemctl-daemon-reload]', :immediately
  notifies :restart, 'service[docker]', :delayed
end

execute 'systemctl-daemon-reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

# Set up Docker cleanup cron job
cron 'docker-system-prune' do
  minute '0'
  hour '3'
  weekday '0' if node['vectorflow']['docker']['prune_schedule'] == 'weekly'
  command 'docker system prune -af --filter "until=168h" > /var/log/docker-prune.log 2>&1'
  user 'root'
end

log 'docker_configure_complete' do
  message 'Docker daemon configured successfully'
  level :info
end
