#
# Cookbook:: vectorflow_base
# Recipe:: ntp
#
# Configures time synchronization
#

# Install and configure NTP/chrony based on platform
case node['platform_family']
when 'debian'
  package 'chrony' do
    action :install
  end

  template '/etc/chrony/chrony.conf' do
    source 'chrony.conf.erb'
    owner 'root'
    group 'root'
    mode '0644'
    variables(ntp_servers: node['vectorflow']['base']['ntp_servers'])
    notifies :restart, 'service[chrony]', :delayed
  end

  service 'chrony' do
    action [:enable, :start]
  end

when 'rhel', 'amazon'
  package 'chrony' do
    action :install
  end

  template '/etc/chrony.conf' do
    source 'chrony.conf.erb'
    owner 'root'
    group 'root'
    mode '0644'
    variables(ntp_servers: node['vectorflow']['base']['ntp_servers'])
    notifies :restart, 'service[chronyd]', :delayed
  end

  service 'chronyd' do
    action [:enable, :start]
  end
end

log 'ntp_complete' do
  message 'VectorFlow time synchronization configured successfully'
  level :info
end
