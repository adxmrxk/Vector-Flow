#
# Cookbook:: vectorflow_docker
# Recipe:: compose
#
# Installs Docker Compose
#

compose_version = node['vectorflow']['docker']['compose_version']

# Install Docker Compose plugin (v2)
execute 'install-docker-compose-plugin' do
  command <<-CMD
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/download/v#{compose_version}/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  CMD
  creates '/usr/local/lib/docker/cli-plugins/docker-compose'
  not_if "docker compose version | grep -q #{compose_version}"
end

# Create symlink for standalone docker-compose command
link '/usr/local/bin/docker-compose' do
  to '/usr/local/lib/docker/cli-plugins/docker-compose'
  link_type :symbolic
end

# Verify installation
execute 'verify-docker-compose' do
  command 'docker compose version'
  action :run
end

log 'docker_compose_complete' do
  message "Docker Compose v#{compose_version} installed successfully"
  level :info
end
