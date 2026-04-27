#
# Cookbook:: vectorflow_security
# Recipe:: compliance_check
#
# Sets up compliance checking and drift detection
#

compliance_config = node['vectorflow']['security']['compliance']

# Create compliance check script
template '/usr/local/bin/vectorflow-compliance-check' do
  source 'compliance-check.sh.erb'
  owner 'root'
  group 'root'
  mode '0750'
  variables(
    cis_benchmark: compliance_config['cis_benchmark'],
    log_dir: node['vectorflow']['base']['log_dir']
  )
end

# Create compliance report directory
directory "#{node['vectorflow']['base']['log_dir']}/compliance" do
  owner 'root'
  group node['vectorflow']['base']['group']
  mode '0750'
  recursive true
end

# Schedule compliance check
cron 'vectorflow-compliance-check' do
  minute '0'
  hour '6'
  command '/usr/local/bin/vectorflow-compliance-check >> /var/log/vectorflow/compliance/check.log 2>&1'
  user 'root'
  only_if { compliance_config['check_interval'] == 'daily' }
end

# Create drift detection script
template '/usr/local/bin/vectorflow-drift-detection' do
  source 'drift-detection.sh.erb'
  owner 'root'
  group 'root'
  mode '0750'
  variables(
    config_dir: node['vectorflow']['base']['config_dir'],
    log_dir: node['vectorflow']['base']['log_dir']
  )
end

# Schedule drift detection
cron 'vectorflow-drift-detection' do
  minute '*/30'
  command '/usr/local/bin/vectorflow-drift-detection >> /var/log/vectorflow/compliance/drift.log 2>&1'
  user 'root'
end

log 'compliance_check_complete' do
  message 'Compliance checking configured successfully'
  level :info
end
