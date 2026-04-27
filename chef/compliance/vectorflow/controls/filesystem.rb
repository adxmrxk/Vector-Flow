# =================================
# VectorFlow Filesystem Compliance Controls
# =================================

control 'fs-01' do
  impact 1.0
  title 'Critical files should have correct permissions'
  desc 'System files must have appropriate permissions set'

  describe file('/etc/passwd') do
    its('mode') { should cmp '0644' }
    its('owner') { should eq 'root' }
  end

  describe file('/etc/shadow') do
    its('mode') { should cmp '0640' }
    its('owner') { should eq 'root' }
  end

  describe file('/etc/ssh/sshd_config') do
    its('mode') { should cmp '0600' }
    its('owner') { should eq 'root' }
  end
end

control 'fs-02' do
  impact 0.7
  title 'VectorFlow directories should exist'
  desc 'All required VectorFlow directories must be present'

  %w[/opt/vectorflow /var/log/vectorflow /var/lib/vectorflow /etc/vectorflow].each do |dir|
    describe file(dir) do
      it { should be_directory }
    end
  end
end

control 'fs-03' do
  impact 0.5
  title 'VectorFlow directories should have correct ownership'
  desc 'VectorFlow directories should be owned by the vectorflow user'

  describe file('/opt/vectorflow') do
    its('owner') { should eq 'vectorflow' }
    its('group') { should eq 'vectorflow' }
  end

  describe file('/var/log/vectorflow') do
    its('owner') { should eq 'vectorflow' }
  end
end

control 'fs-04' do
  impact 0.7
  title 'No world-writable files in VectorFlow directories'
  desc 'World-writable files are a security risk'

  describe command('find /opt/vectorflow -type f -perm -0002 2>/dev/null') do
    its('stdout') { should be_empty }
  end
end
