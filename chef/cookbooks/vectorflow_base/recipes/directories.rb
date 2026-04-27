#
# Cookbook:: vectorflow_base
# Recipe:: directories
#
# Creates the VectorFlow directory structure
#

# Application directory
directory node['vectorflow']['base']['app_dir'] do
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0755'
  recursive true
  action :create
end

# Log directory
directory node['vectorflow']['base']['log_dir'] do
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0755'
  recursive true
  action :create
end

# Data directory
directory node['vectorflow']['base']['data_dir'] do
  owner node['vectorflow']['base']['user']
  group node['vectorflow']['base']['group']
  mode '0755'
  recursive true
  action :create
end

# Config directory
directory node['vectorflow']['base']['config_dir'] do
  owner 'root'
  group node['vectorflow']['base']['group']
  mode '0750'
  recursive true
  action :create
end

# Create subdirectories
%w[models cache tmp].each do |subdir|
  directory "#{node['vectorflow']['base']['data_dir']}/#{subdir}" do
    owner node['vectorflow']['base']['user']
    group node['vectorflow']['base']['group']
    mode '0755'
    action :create
  end
end

log 'directories_complete' do
  message 'VectorFlow directory structure created successfully'
  level :info
end
