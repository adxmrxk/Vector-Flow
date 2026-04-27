# =================================
# VectorFlow SSH Compliance Controls
# =================================

control 'ssh-01' do
  impact 1.0
  title 'SSH root login should be disabled'
  desc 'Root login via SSH should be disabled for security'

  describe sshd_config do
    its('PermitRootLogin') { should eq 'no' }
  end
end

control 'ssh-02' do
  impact 1.0
  title 'SSH password authentication should be disabled'
  desc 'Password authentication should be disabled in favor of key-based auth'

  describe sshd_config do
    its('PasswordAuthentication') { should eq 'no' }
  end
end

control 'ssh-03' do
  impact 0.7
  title 'SSH should use Protocol 2'
  desc 'SSH Protocol 1 has known vulnerabilities'

  describe sshd_config do
    its('Protocol') { should cmp 2 }
  end
end

control 'ssh-04' do
  impact 0.5
  title 'SSH MaxAuthTries should be limited'
  desc 'Limit authentication attempts to prevent brute force attacks'

  describe sshd_config do
    its('MaxAuthTries') { should cmp <= 4 }
  end
end

control 'ssh-05' do
  impact 0.5
  title 'SSH X11 forwarding should be disabled'
  desc 'X11 forwarding can be used to tunnel connections'

  describe sshd_config do
    its('X11Forwarding') { should eq 'no' }
  end
end
