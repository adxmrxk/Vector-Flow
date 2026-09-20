# InSpec tests for the `security` Test Kitchen suite.
# Run list: vectorflow_base::default, vectorflow_security::default
# Suite attribute override: security.firewall.enabled = false
#
# Because this suite disables the firewall attribute, firewall.rb returns
# before running any `ufw` commands (see firewall.rb: `return unless
# ...firewall.enabled`). These tests deliberately do NOT assert anything
# about ufw being enabled/active — only that the package installed, which
# packages.rb does unconditionally.

title 'vectorflow_security'

control 'security-packages-01' do
  impact 0.8
  title 'Security tooling packages are installed'
  desc 'packages.rb installs every entry in security/packages'

  %w(fail2ban ufw auditd rkhunter chkrootkit).each do |pkg|
    describe package(pkg) do
      it { should be_installed }
    end
  end
end

control 'security-packages-02' do
  impact 0.6
  title 'Legacy unencrypted remote-access clients are removed'
  desc 'packages.rb purges telnet and the rsh clients as a security risk'

  %w(telnet rsh-client).each do |pkg|
    describe package(pkg) do
      it { should_not be_installed }
    end
  end
end

control 'security-firewall-01' do
  impact 0.3
  title 'ufw is installed but left untouched when the firewall attribute is disabled'
  desc 'This suite sets security.firewall.enabled=false; firewall.rb must not enable ufw in that case'

  describe command('ufw status') do
    its('stdout') { should_not match(/Status: active/) }
  end
end

control 'security-ssh-01' do
  impact 1.0
  title 'sshd is hardened per security/ssh attributes'
  desc 'ssh.rb templates sshd_config from security/ssh and keeps sshd running'

  describe sshd_config('/etc/ssh/sshd_config') do
    its('PermitRootLogin') { should cmp 'no' }
    its('PasswordAuthentication') { should cmp 'no' }
    its('X11Forwarding') { should cmp 'no' }
    its('MaxAuthTries') { should cmp '3' }
  end

  describe file('/etc/ssh/sshd_config') do
    its('mode') { should cmp '0600' }
  end

  describe file('/etc/ssh/sshd_config.backup') do
    it { should exist }
  end

  describe service('ssh') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'security-fail2ban-01' do
  impact 0.9
  title 'fail2ban is configured with the attribute-driven jail settings and running'
  desc 'fail2ban.rb templates jail.local/jail.d from security/fail2ban and enables the service'

  describe file('/etc/fail2ban/jail.local') do
    it { should exist }
    its('content') { should match(/bantime\s*=\s*1h/) }
    its('content') { should match(/findtime\s*=\s*10m/) }
    its('content') { should match(/maxretry\s*=\s*5/) }
  end

  describe file('/etc/fail2ban/jail.d/vectorflow.conf') do
    it { should exist }
  end

  describe service('fail2ban') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'security-audit-01' do
  impact 0.8
  title 'auditd is configured and running with VectorFlow-specific rules'
  desc 'audit.rb templates auditd.conf and vectorflow.rules, then enables auditd'

  describe file('/etc/audit/auditd.conf') do
    it { should exist }
    its('content') { should match(%r{/var/log/audit/audit\.log}) }
  end

  describe file('/etc/audit/rules.d/vectorflow.rules') do
    it { should exist }
  end

  describe service('auditd') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'security-auto-updates-01' do
  impact 0.6
  title 'Unattended security upgrades are installed and enabled'
  desc 'auto_updates.rb installs unattended-upgrades and templates its apt config'

  describe package('unattended-upgrades') do
    it { should be_installed }
  end

  describe file('/etc/apt/apt.conf.d/50unattended-upgrades') do
    it { should exist }
  end

  describe file('/etc/apt/apt.conf.d/20auto-upgrades') do
    it { should exist }
  end
end

control 'security-compliance-01' do
  impact 0.5
  title 'Compliance and drift-detection scripts are installed and scheduled'
  desc 'compliance_check.rb installs the compliance/drift scripts and cron schedules'

  describe file('/usr/local/bin/vectorflow-compliance-check') do
    it { should exist }
    it { should be_executable }
  end

  describe file('/usr/local/bin/vectorflow-drift-detection') do
    it { should exist }
    it { should be_executable }
  end

  describe directory('/var/log/vectorflow/compliance') do
    it { should exist }
    it { should be_owned_by 'root' }
  end

  describe cron do
    with(user: 'root')
    its('commands') { should include(match(/vectorflow-compliance-check/)) }
    its('commands') { should include(match(/vectorflow-drift-detection/)) }
  end
end
