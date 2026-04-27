#
# Cookbook:: vectorflow_base
# Recipe:: default
#
# Copyright:: 2024, VectorFlow Team
# License:: MIT
#

# Include component recipes
include_recipe 'vectorflow_base::packages'
include_recipe 'vectorflow_base::users'
include_recipe 'vectorflow_base::directories'
include_recipe 'vectorflow_base::sysctl'
include_recipe 'vectorflow_base::limits'
include_recipe 'vectorflow_base::ntp'
