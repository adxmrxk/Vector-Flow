#
# Cookbook:: vectorflow_security
# Recipe:: auto_updates
#
# Configures automatic security updates
#

return unless node['vectorflow']['security']['auto_updates']['enabled']

case node['platform_family']
when 'debian'
  package 'unattended-upgrades' do
    action :install
  end

  template '/etc/apt/apt.conf.d/50unattended-upgrades' do
    source 'unattended-upgrades.erb'
    owner 'root'
    group 'root'
    mode '0644'
    variables(
      security_only: node['vectorflow']['security']['auto_updates']['security_only'],
      reboot_if_needed: node['vectorflow']['security']['auto_updates']['reboot_if_needed']
    )
  end

  template '/etc/apt/apt.conf.d/20auto-upgrades' do
    source 'auto-upgrades.erb'
    owner 'root'
    group 'root'
    mode '0644'
  end

  service 'unattended-upgrades' do
    action [:enable, :start]
  end

when 'rhel', 'amazon'
  package 'dnf-automatic' do
    action :install
  end

  template '/etc/dnf/automatic.conf' do
    source 'dnf-automatic.conf.erb'
    owner 'root'
    group 'root'
    mode '0644'
    variables(
      security_only: node['vectorflow']['security']['auto_updates']['security_only']
    )
  end

  service 'dnf-automatic.timer' do
    action [:enable, :start]
  end
end

log 'auto_updates_complete' do
  message 'Automatic security updates configured successfully'
  level :info
end
