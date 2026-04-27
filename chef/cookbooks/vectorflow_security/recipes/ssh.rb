#
# Cookbook:: vectorflow_security
# Recipe:: ssh
#
# Configures SSH for security
#

ssh_config = node['vectorflow']['security']['ssh']

# Backup original sshd_config
execute 'backup-sshd-config' do
  command 'cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup'
  creates '/etc/ssh/sshd_config.backup'
end

# Configure SSH daemon
template '/etc/ssh/sshd_config' do
  source 'sshd_config.erb'
  owner 'root'
  group 'root'
  mode '0600'
  variables(ssh_config: ssh_config)
  notifies :restart, 'service[sshd]', :delayed
end

# Ensure SSH service is running
service 'sshd' do
  service_name node['platform_family'] == 'debian' ? 'ssh' : 'sshd'
  action [:enable, :start]
end

# Set correct permissions on SSH directories
directory '/etc/ssh' do
  owner 'root'
  group 'root'
  mode '0755'
end

# Secure SSH host keys
%w[ssh_host_rsa_key ssh_host_ecdsa_key ssh_host_ed25519_key].each do |key|
  file "/etc/ssh/#{key}" do
    mode '0600'
    only_if { ::File.exist?("/etc/ssh/#{key}") }
  end
end

log 'ssh_hardening_complete' do
  message 'SSH hardening completed successfully'
  level :info
end
