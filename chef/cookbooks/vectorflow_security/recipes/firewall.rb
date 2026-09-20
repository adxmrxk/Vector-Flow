#
# Cookbook:: vectorflow_security
# Recipe:: firewall
#
# Configures UFW firewall
#

return unless node['vectorflow']['security']['firewall']['enabled']

firewall_config = node['vectorflow']['security']['firewall']

# Enable UFW
execute 'enable-ufw' do
  command 'ufw --force enable'
  not_if 'ufw status | grep -q "Status: active"'
  only_if { platform_family?('debian') }
end

# Set default policies
execute 'ufw-default-deny-incoming' do
  command 'ufw default deny incoming'
  only_if { platform_family?('debian') }
end

execute 'ufw-default-allow-outgoing' do
  command 'ufw default allow outgoing'
  only_if { platform_family?('debian') }
end

# Allow configured ports
# `ufw allow` takes a single port and a "start:end" range identically, so one
# resource covers both cases.
firewall_config['allowed_ports'].each do |name, port|
  execute "ufw-allow-#{name}" do
    command "ufw allow #{port}/tcp"
    not_if "ufw status | grep -q '#{port}/tcp'"
    only_if { platform_family?('debian') }
  end
end

# Allow Docker network communication
execute 'ufw-allow-docker' do
  command 'ufw allow from 172.17.0.0/16'
  not_if 'ufw status | grep -q "172.17.0.0/16"'
  only_if { platform_family?('debian') }
end

# Allow Kubernetes pod network
execute 'ufw-allow-k8s-pods' do
  command 'ufw allow from 10.244.0.0/16'
  not_if 'ufw status | grep -q "10.244.0.0/16"'
  only_if { platform_family?('debian') }
end

# Reload UFW
execute 'ufw-reload' do
  command 'ufw reload'
  only_if { platform_family?('debian') }
end

log 'firewall_complete' do
  message 'Firewall configured successfully'
  level :info
end
