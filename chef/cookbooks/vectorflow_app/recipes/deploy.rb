#
# Cookbook:: vectorflow_app
# Recipe:: deploy
#
# Deploys VectorFlow services to Kubernetes
#

app_config = node['vectorflow']['app']

# Ensure namespace exists
execute 'create-namespace' do
  command 'kubectl create namespace vectorflow --dry-run=client -o yaml | kubectl apply -f -'
  only_if 'kubectl cluster-info'
end

# Deploy each enabled service
app_config['services'].each do |service_name, config|
  next unless config['enabled']

  # Generate deployment manifest
  template "#{node['vectorflow']['base']['config_dir']}/k8s-#{service_name}.yaml" do
    source 'k8s-deployment.yaml.erb'
    owner 'root'
    group node['vectorflow']['base']['group']
    mode '0640'
    variables(
      service_name: service_name,
      config: config,
      resources: app_config['resources'][service_name],
      registry: app_config['registry'],
      version: app_config['version']
    )
  end

  # Apply deployment
  execute "deploy-#{service_name}" do
    command "kubectl apply -f #{node['vectorflow']['base']['config_dir']}/k8s-#{service_name}.yaml"
    only_if 'kubectl cluster-info'
  end
end

# Wait for deployments to be ready
app_config['services'].each do |service_name, config|
  next unless config['enabled']

  execute "wait-for-#{service_name}" do
    command "kubectl rollout status deployment/vectorflow-#{service_name} -n vectorflow --timeout=300s"
    only_if 'kubectl cluster-info'
    retries 3
    retry_delay 30
  end
end

log 'deploy_complete' do
  message 'VectorFlow services deployed successfully'
  level :info
end
