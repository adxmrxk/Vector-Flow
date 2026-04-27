#
# Cookbook:: vectorflow_base
# Recipe:: packages
#
# Installs base system packages required for VectorFlow
#

# Update package cache
case node['platform_family']
when 'debian'
  apt_update 'update' do
    frequency 86400
    action :periodic
  end
when 'rhel', 'amazon'
  yum_repository 'epel' do
    description 'Extra Packages for Enterprise Linux'
    mirrorlist 'https://mirrors.fedoraproject.org/metalink?repo=epel-$releasever&arch=$basearch'
    gpgkey 'https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-$releasever'
    enabled true
    only_if { node['platform_version'].to_i >= 8 }
  end
end

# Install required packages
node['vectorflow']['base']['packages'].each do |pkg|
  package pkg do
    action :install
    retries 3
    retry_delay 10
  end
end

# Ensure timezone is set
timezone node['vectorflow']['base']['timezone'] do
  action :set
end

# Configure locale
execute 'generate-locale' do
  command "locale-gen #{node['vectorflow']['base']['locale']}"
  not_if "locale -a | grep -q #{node['vectorflow']['base']['locale'].gsub('.', '\\.')}"
  only_if { node['platform_family'] == 'debian' }
end

log 'base_packages_complete' do
  message 'VectorFlow base packages installed successfully'
  level :info
end
