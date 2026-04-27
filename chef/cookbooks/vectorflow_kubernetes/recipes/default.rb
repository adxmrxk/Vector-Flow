#
# Cookbook:: vectorflow_kubernetes
# Recipe:: default
#
# Copyright:: 2024, VectorFlow Team
# License:: MIT
#

case node['vectorflow']['kubernetes']['node_type']
when 'standalone'
  include_recipe 'vectorflow_kubernetes::minikube'
when 'master'
  include_recipe 'vectorflow_kubernetes::kubeadm'
  include_recipe 'vectorflow_kubernetes::master'
when 'worker'
  include_recipe 'vectorflow_kubernetes::kubeadm'
  include_recipe 'vectorflow_kubernetes::worker'
end

include_recipe 'vectorflow_kubernetes::kubectl'
include_recipe 'vectorflow_kubernetes::helm'
