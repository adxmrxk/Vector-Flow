#
# Cookbook:: vectorflow_kubernetes
# Recipe:: minikube
#
# Installs and configures Minikube for local development
#

minikube_config = node['vectorflow']['kubernetes']['minikube']

# Download and install Minikube
execute 'install-minikube' do
  command <<-CMD
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
  CMD
  creates '/usr/local/bin/minikube'
end

# Configure Minikube defaults
execute 'minikube-config-driver' do
  command "minikube config set driver #{minikube_config['driver']}"
  user node['vectorflow']['base']['user']
  environment 'HOME' => node['vectorflow']['base']['home']
end

execute 'minikube-config-cpus' do
  command "minikube config set cpus #{minikube_config['cpus']}"
  user node['vectorflow']['base']['user']
  environment 'HOME' => node['vectorflow']['base']['home']
end

execute 'minikube-config-memory' do
  command "minikube config set memory #{minikube_config['memory']}"
  user node['vectorflow']['base']['user']
  environment 'HOME' => node['vectorflow']['base']['home']
end

execute 'minikube-config-disk-size' do
  command "minikube config set disk-size #{minikube_config['disk_size']}"
  user node['vectorflow']['base']['user']
  environment 'HOME' => node['vectorflow']['base']['home']
end

# Create Minikube start script
template '/usr/local/bin/vectorflow-minikube-start' do
  source 'minikube-start.sh.erb'
  owner 'root'
  group 'root'
  mode '0755'
  variables(
    minikube_config: minikube_config,
    vectorflow_user: node['vectorflow']['base']['user']
  )
end

# Create Minikube stop script
template '/usr/local/bin/vectorflow-minikube-stop' do
  source 'minikube-stop.sh.erb'
  owner 'root'
  group 'root'
  mode '0755'
end

log 'minikube_complete' do
  message 'Minikube installed and configured successfully'
  level :info
end
