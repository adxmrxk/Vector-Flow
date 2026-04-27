#
# Cookbook:: vectorflow_kubernetes
# Recipe:: kubeadm
#
# Installs kubeadm, kubelet, and kubectl for cluster setup
#

k8s_version = node['vectorflow']['kubernetes']['version']

# Disable swap (required for Kubernetes)
execute 'disable-swap' do
  command 'swapoff -a'
  not_if 'free | grep -q "Swap:.*0.*0.*0"'
end

# Remove swap from fstab
ruby_block 'remove-swap-fstab' do
  block do
    fstab = '/etc/fstab'
    if ::File.exist?(fstab)
      content = ::File.read(fstab)
      new_content = content.lines.reject { |line| line.include?('swap') }.join
      ::File.write(fstab, new_content)
    end
  end
end

# Load required kernel modules
%w[overlay br_netfilter].each do |mod|
  execute "modprobe-#{mod}" do
    command "modprobe #{mod}"
    not_if "lsmod | grep -q #{mod}"
  end
end

# Persist kernel modules
file '/etc/modules-load.d/k8s.conf' do
  content "overlay\nbr_netfilter\n"
  owner 'root'
  group 'root'
  mode '0644'
end

# Configure sysctl for Kubernetes networking
file '/etc/sysctl.d/k8s.conf' do
  content <<-CONF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
  CONF
  owner 'root'
  group 'root'
  mode '0644'
  notifies :run, 'execute[reload-k8s-sysctl]', :immediately
end

execute 'reload-k8s-sysctl' do
  command 'sysctl --system'
  action :nothing
end

case node['platform_family']
when 'debian'
  # Add Kubernetes repository
  execute 'add-k8s-gpg-key' do
    command <<-CMD
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v#{k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    CMD
    creates '/etc/apt/keyrings/kubernetes-apt-keyring.gpg'
  end

  file '/etc/apt/sources.list.d/kubernetes.list' do
    content "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v#{k8s_version}/deb/ /"
    owner 'root'
    group 'root'
    mode '0644'
    notifies :run, 'execute[apt-update-k8s]', :immediately
  end

  execute 'apt-update-k8s' do
    command 'apt-get update'
    action :nothing
  end

  %w[kubelet kubeadm kubectl].each do |pkg|
    package pkg do
      action :install
    end
  end

  # Hold Kubernetes packages to prevent auto-update
  execute 'hold-k8s-packages' do
    command 'apt-mark hold kubelet kubeadm kubectl'
    action :run
  end

when 'rhel', 'amazon'
  yum_repository 'kubernetes' do
    description 'Kubernetes Repository'
    baseurl "https://pkgs.k8s.io/core:/stable:/v#{k8s_version}/rpm/"
    gpgkey "https://pkgs.k8s.io/core:/stable:/v#{k8s_version}/rpm/repodata/repomd.xml.key"
    gpgcheck true
    enabled true
  end

  %w[kubelet kubeadm kubectl].each do |pkg|
    package pkg do
      action :install
    end
  end
end

# Enable and start kubelet
service 'kubelet' do
  action [:enable, :start]
end

log 'kubeadm_complete' do
  message 'kubeadm, kubelet, and kubectl installed successfully'
  level :info
end
