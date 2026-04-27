#
# Cookbook:: vectorflow_security
# Recipe:: packages
#
# Installs security-related packages
#

# Install security packages
node['vectorflow']['security']['packages'].each do |pkg|
  package pkg do
    action :install
    retries 3
    retry_delay 10
  end
end

# Remove unnecessary packages that could be security risks
%w[telnet rsh-client rsh-redone-client].each do |pkg|
  package pkg do
    action :purge
    only_if { node['platform_family'] == 'debian' }
  end
end

log 'security_packages_complete' do
  message 'Security packages installed successfully'
  level :info
end
