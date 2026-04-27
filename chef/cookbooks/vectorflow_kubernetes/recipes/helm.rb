#
# Cookbook:: vectorflow_kubernetes
# Recipe:: helm
#
# Installs Helm package manager
#

helm_version = node['vectorflow']['kubernetes']['helm']['version']

# Download and install Helm
execute 'install-helm' do
  command <<-CMD
    curl -fsSL https://get.helm.sh/helm-v#{helm_version}-linux-amd64.tar.gz -o /tmp/helm.tar.gz
    tar -zxvf /tmp/helm.tar.gz -C /tmp
    mv /tmp/linux-amd64/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm
    rm -rf /tmp/linux-amd64 /tmp/helm.tar.gz
  CMD
  creates '/usr/local/bin/helm'
  not_if "helm version | grep -q #{helm_version}"
end

# Add Helm repositories
node['vectorflow']['kubernetes']['helm']['repositories'].each do |name, url|
  execute "helm-repo-add-#{name}" do
    command "helm repo add #{name} #{url}"
    user node['vectorflow']['base']['user']
    environment 'HOME' => node['vectorflow']['base']['home']
    not_if "helm repo list | grep -q #{name}"
  end
end

# Update Helm repositories
execute 'helm-repo-update' do
  command 'helm repo update'
  user node['vectorflow']['base']['user']
  environment 'HOME' => node['vectorflow']['base']['home']
  action :run
end

log 'helm_complete' do
  message "Helm v#{helm_version} installed and configured successfully"
  level :info
end
