# =================================
# VectorFlow Docker Compliance Controls
# =================================

control 'docker-01' do
  impact 1.0
  title 'Docker daemon should be running'
  desc 'Docker service must be active for container operations'

  describe service('docker') do
    it { should be_installed }
    it { should be_enabled }
    it { should be_running }
  end
end

control 'docker-02' do
  impact 0.7
  title 'Docker daemon configuration should exist'
  desc 'Docker should have a daemon.json configuration file'

  describe file('/etc/docker/daemon.json') do
    it { should exist }
    its('mode') { should cmp '0644' }
  end
end

control 'docker-03' do
  impact 0.5
  title 'Docker should use overlay2 storage driver'
  desc 'Overlay2 is the recommended storage driver for performance'

  describe json('/etc/docker/daemon.json') do
    its(['storage-driver']) { should eq 'overlay2' }
  end
end

control 'docker-04' do
  impact 0.5
  title 'Docker logging should be configured'
  desc 'Docker should have logging configured for troubleshooting'

  describe json('/etc/docker/daemon.json') do
    its(['log-driver']) { should eq 'json-file' }
  end
end

control 'docker-05' do
  impact 0.7
  title 'VectorFlow user should be in docker group'
  desc 'The vectorflow user needs docker group membership'

  describe user('vectorflow') do
    it { should exist }
    its('groups') { should include 'docker' }
  end
end
