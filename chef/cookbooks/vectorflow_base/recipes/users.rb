#
# Cookbook:: vectorflow_base
# Recipe:: users
#
# Creates the VectorFlow service user and group
#

# Create vectorflow group
group node['vectorflow']['base']['group'] do
  system true
  action :create
end

# Create vectorflow user
user node['vectorflow']['base']['user'] do
  comment 'VectorFlow Service Account'
  home node['vectorflow']['base']['home']
  shell node['vectorflow']['base']['shell']
  gid node['vectorflow']['base']['group']
  system true
  manage_home true
  action :create
end

# Create .ssh directory for the user
directory "#{node['vectorflow']['base']['home']}/.ssh" do
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0700'
  action :create
end

# Create authorized_keys file
file "#{node['vectorflow']['base']['home']}/.ssh/authorized_keys" do
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0600'
  action :create_if_missing
end

# Add vectorflow user to docker group if it exists
group 'docker' do
  members [node['vectorflow']['base']['user']]
  append true
  action :modify
  only_if 'getent group docker'
end

log 'users_complete' do
  message "VectorFlow user '#{node['vectorflow']['base']['user']}' created successfully"
  level :info
end
