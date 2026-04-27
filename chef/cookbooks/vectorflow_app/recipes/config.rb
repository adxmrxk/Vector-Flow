#
# Cookbook:: vectorflow_app
# Recipe:: config
#
# Generates VectorFlow application configuration
#

# Create configuration directory
directory node['vectorflow']['base']['config_dir'] do
  owner 'root'
  group node['vectorflow']['base']['group']
  mode '0750'
  recursive true
end

# Generate main configuration file
template "#{node['vectorflow']['base']['config_dir']}/vectorflow.yaml" do
  source 'vectorflow.yaml.erb'
  owner 'root'
  group node['vectorflow']['base']['group']
  mode '0640'
  variables(
    services: node['vectorflow']['app']['services'],
    model: node['vectorflow']['app']['model'],
    pinecone: node['vectorflow']['app']['pinecone'],
    logging: node['vectorflow']['app']['logging']
  )
end

# Generate environment file for Docker/systemd
template "#{node['vectorflow']['base']['config_dir']}/vectorflow.env" do
  source 'vectorflow.env.erb'
  owner 'root'
  group node['vectorflow']['base']['group']
  mode '0640'
  sensitive true
  variables(
    model: node['vectorflow']['app']['model'],
    pinecone: node['vectorflow']['app']['pinecone'],
    logging: node['vectorflow']['app']['logging']
  )
end

# Create Kubernetes ConfigMap from config
execute 'create-configmap' do
  command <<-CMD
    kubectl create configmap vectorflow-config \
      --from-file=#{node['vectorflow']['base']['config_dir']}/vectorflow.yaml \
      --namespace=vectorflow \
      --dry-run=client -o yaml | kubectl apply -f -
  CMD
  only_if 'kubectl cluster-info'
end

log 'config_complete' do
  message 'VectorFlow configuration generated successfully'
  level :info
end
