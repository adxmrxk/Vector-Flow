#
# Cookbook:: vectorflow_kubernetes
# Recipe:: kubectl
#
# Installs kubectl CLI
#

k8s_version = node['vectorflow']['kubernetes']['version']

# Download and install kubectl
execute 'install-kubectl' do
  command <<-CMD
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/kubectl
  CMD
  creates '/usr/local/bin/kubectl'
end

# Create kubectl config directory for vectorflow user
directory "#{node['vectorflow']['base']['home']}/.kube" do
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0700'
  action :create
end

# Enable kubectl autocompletion
template '/etc/bash_completion.d/kubectl' do
  source 'kubectl-completion.erb'
  owner 'root'
  group 'root'
  mode '0644'
end

# Create kubectl aliases
template "#{node['vectorflow']['base']['home']}/.kubectl_aliases" do
  source 'kubectl-aliases.erb'
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0644'
end

# Add aliases to bashrc
ruby_block 'add-kubectl-aliases-to-bashrc' do
  block do
    bashrc = "#{node['vectorflow']['base']['home']}/.bashrc"
    if ::File.exist?(bashrc)
      content = ::File.read(bashrc)
      unless content.include?('.kubectl_aliases')
        ::File.open(bashrc, 'a') do |f|
          f.puts "\n# kubectl aliases"
          f.puts "[ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases"
        end
      end
    end
  end
end

log 'kubectl_complete' do
  message 'kubectl installed and configured successfully'
  level :info
end
