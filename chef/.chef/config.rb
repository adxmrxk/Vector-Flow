# =================================
# VectorFlow Chef Configuration
# =================================
# Local Chef configuration for knife and chef-client
#
# For Chef Server configuration, update the following:
#   - chef_server_url
#   - node_name
#   - client_key

# Chef repository paths
current_dir = File.dirname(__FILE__)
cookbook_path ["#{current_dir}/../cookbooks"]
role_path "#{current_dir}/../roles"
environment_path "#{current_dir}/../environments"
data_bag_path "#{current_dir}/../data_bags"
policy_path "#{current_dir}/../policies"

# Local mode settings (Chef Zero)
local_mode true
chef_zero.enabled true

# Logging
log_level :info
log_location STDOUT

# Chef Server settings (uncomment for production)
# chef_server_url 'https://chef-server.vectorflow.local/organizations/vectorflow'
# node_name 'your-node-name'
# client_key "#{current_dir}/your-node-name.pem"
# validation_client_name 'vectorflow-validator'
# validation_key "#{current_dir}/vectorflow-validator.pem"

# SSL verification (set to true in production)
ssl_verify_mode :verify_none

# Cookbook versioning
cookbook_copyright 'VectorFlow Team'
cookbook_license 'MIT'
cookbook_email 'team@vectorflow.local'
