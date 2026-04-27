#
# Cookbook:: vectorflow_docker
# Recipe:: install
#
# Installs Docker Engine
#

# Remove old versions
%w[docker docker-engine docker.io containerd runc].each do |pkg|
  package pkg do
    action :purge
    only_if { node['platform_family'] == 'debian' }
  end
end

case node['platform_family']
when 'debian'
  # Add Docker GPG key
  execute 'add-docker-gpg-key' do
    command <<-CMD
      curl -fsSL https://download.docker.com/linux/#{node['platform']}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    CMD
    creates '/usr/share/keyrings/docker-archive-keyring.gpg'
  end

  # Add Docker repository
  file '/etc/apt/sources.list.d/docker.list' do
    content "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/#{node['platform']} #{node['lsb']['codename']} stable"
    owner 'root'
    group 'root'
    mode '0644'
    notifies :run, 'execute[apt-update-docker]', :immediately
  end

  execute 'apt-update-docker' do
    command 'apt-get update'
    action :nothing
  end

  # Install Docker packages
  %w[docker-ce docker-ce-cli containerd.io docker-buildx-plugin].each do |pkg|
    package pkg do
      action :install
      options '--allow-downgrades' if node['vectorflow']['docker']['version'] != ''
      version node['vectorflow']['docker']['version'] if node['vectorflow']['docker']['version'] != '' && pkg == 'docker-ce'
    end
  end

when 'rhel', 'amazon'
  # Add Docker repository
  yum_repository 'docker-ce' do
    description 'Docker CE Stable'
    baseurl "https://download.docker.com/linux/centos/$releasever/$basearch/stable"
    gpgkey 'https://download.docker.com/linux/centos/gpg'
    gpgcheck true
    enabled true
  end

  # Install Docker packages
  %w[docker-ce docker-ce-cli containerd.io docker-buildx-plugin].each do |pkg|
    package pkg do
      action :install
    end
  end
end

# Ensure Docker service is enabled and started
service 'docker' do
  action [:enable, :start]
end

# Add vectorflow user to docker group
group 'docker' do
  members [node['vectorflow']['base']['user']]
  append true
  action :modify
  notifies :restart, 'service[docker]', :delayed
end

log 'docker_install_complete' do
  message 'Docker installed successfully'
  level :info
end
