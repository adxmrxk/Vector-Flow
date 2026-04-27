#
# Cookbook:: vectorflow_base
# Recipe:: limits
#
# Configures system resource limits for VectorFlow services
#

# Create limits configuration for vectorflow user
template '/etc/security/limits.d/99-vectorflow.conf' do
  source 'limits.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    user: node['vectorflow']['base']['user'],
    limits: node['vectorflow']['base']['limits']
  )
end

# Ensure PAM is configured to use limits
file '/etc/pam.d/common-session' do
  content lazy {
    original = ::File.read('/etc/pam.d/common-session')
    if original.include?('pam_limits.so')
      original
    else
      original + "\nsession required pam_limits.so\n"
    end
  }
  only_if { ::File.exist?('/etc/pam.d/common-session') }
end

log 'limits_complete' do
  message 'VectorFlow resource limits configured successfully'
  level :info
end
