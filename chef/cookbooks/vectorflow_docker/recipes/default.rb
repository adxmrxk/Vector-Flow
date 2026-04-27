#
# Cookbook:: vectorflow_docker
# Recipe:: default
#
# Copyright:: 2024, VectorFlow Team
# License:: MIT
#

include_recipe 'vectorflow_docker::install'
include_recipe 'vectorflow_docker::configure'
include_recipe 'vectorflow_docker::compose'
include_recipe 'vectorflow_docker::networks'
