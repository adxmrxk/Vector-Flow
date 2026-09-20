# InSpec tests for the `base` Test Kitchen suite.
# Run list: vectorflow_base::default
#
# These assert the actual state vectorflow_base's recipes converge to, based
# on the recipes and attributes in cookbooks/vectorflow_base — not a generic
# checklist.

title 'vectorflow_base'

control 'base-users-01' do
  impact 1.0
  title 'VectorFlow service group and user exist'
  desc 'users.rb creates a system group and user named after base/user, base/group'

  describe group('vectorflow') do
    it { should exist }
  end

  describe user('vectorflow') do
    it { should exist }
    its('group') { should eq 'vectorflow' }
    its('home') { should eq '/home/vectorflow' }
    its('shell') { should eq '/bin/bash' }
  end
end

control 'base-users-02' do
  impact 0.5
  title 'VectorFlow user has an SSH directory with correct permissions'
  desc 'users.rb creates ~/.ssh (0700) and an authorized_keys file (0600) for the service account'

  describe file('/home/vectorflow/.ssh') do
    it { should be_directory }
    it { should be_owned_by 'vectorflow' }
    its('mode') { should cmp '0700' }
  end

  describe file('/home/vectorflow/.ssh/authorized_keys') do
    it { should exist }
    its('mode') { should cmp '0600' }
  end
end

control 'base-packages-01' do
  impact 1.0
  title 'Base system packages are installed'
  desc 'packages.rb installs every package listed in base/packages'

  %w(curl wget git vim htop jq unzip ca-certificates gnupg).each do |pkg|
    describe package(pkg) do
      it { should be_installed }
    end
  end
end

control 'base-directories-01' do
  impact 1.0
  title 'VectorFlow directory structure exists with the right ownership'
  desc 'directories.rb creates app/log/data dirs owned by vectorflow, and a root-owned config dir'

  describe directory('/opt/vectorflow') do
    it { should exist }
    it { should be_owned_by 'vectorflow' }
    its('mode') { should cmp '0755' }
  end

  describe directory('/var/log/vectorflow') do
    it { should exist }
    it { should be_owned_by 'vectorflow' }
  end

  describe directory('/var/lib/vectorflow') do
    it { should exist }
    it { should be_owned_by 'vectorflow' }
  end

  describe directory('/etc/vectorflow') do
    it { should exist }
    it { should be_owned_by 'root' }
    its('mode') { should cmp '0750' }
  end
end

control 'base-directories-02' do
  impact 0.7
  title 'Data subdirectories for models, cache and tmp exist'
  desc 'directories.rb creates %w(models cache tmp) under base/data_dir'

  %w(models cache tmp).each do |subdir|
    describe directory("/var/lib/vectorflow/#{subdir}") do
      it { should exist }
      it { should be_owned_by 'vectorflow' }
    end
  end
end

control 'base-sysctl-01' do
  impact 0.8
  title 'Kernel performance tuning is applied and persisted'
  desc 'sysctl.rb applies base/sysctl at runtime and writes a drop-in that survives reboot'

  describe file('/etc/sysctl.d/99-vectorflow.conf') do
    it { should exist }
    its('content') { should match(/vm\.swappiness\s*=\s*10/) }
    its('content') { should match(/vm\.max_map_count\s*=\s*262144/) }
  end

  describe kernel_parameter('vm.swappiness') do
    its('value') { should eq 10 }
  end

  describe kernel_parameter('vm.max_map_count') do
    its('value') { should eq 262_144 }
  end
end

control 'base-limits-01' do
  impact 0.6
  title 'File descriptor and process limits are configured for the vectorflow user'
  desc 'limits.rb templates /etc/security/limits.d/99-vectorflow.conf from base/limits'

  describe file('/etc/security/limits.d/99-vectorflow.conf') do
    it { should exist }
    its('content') { should match(/vectorflow\s+soft\s+nofile\s+65536/) }
    its('content') { should match(/vectorflow\s+hard\s+nofile\s+65536/) }
  end
end

control 'base-ntp-01' do
  impact 0.5
  title 'Chrony is installed and configured with the expected NTP pool'
  desc 'ntp.rb installs chrony and templates chrony.conf from base/ntp_servers'

  describe package('chrony') do
    it { should be_installed }
  end

  describe file('/etc/chrony/chrony.conf') do
    it { should exist }
    its('content') { should match(/0\.pool\.ntp\.org/) }
  end
end
