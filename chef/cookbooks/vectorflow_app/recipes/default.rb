#
# Cookbook:: vectorflow_app
# Recipe:: default
#
# Copyright:: 2024, VectorFlow Team
# License:: MIT
#
# Deploys and configures VectorFlow application
#

include_recipe 'vectorflow_app::config'
include_recipe 'vectorflow_app::deploy'
include_recipe 'vectorflow_app::monitoring'
