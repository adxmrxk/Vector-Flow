#
# Cookbook:: vectorflow_docker
# Recipe:: networks
#
# Creates Docker networks for VectorFlow
#

node['vectorflow']['docker']['networks'].each do |name, config|
  execute "create-docker-network-#{name}" do
    command <<-CMD
      docker network create \
        --driver #{config['driver']} \
        --subnet #{config['subnet']} \
        #{name}
    CMD
    not_if "docker network inspect #{name}"
  end
end

log 'docker_networks_complete' do
  message 'Docker networks created successfully'
  level :info
end
