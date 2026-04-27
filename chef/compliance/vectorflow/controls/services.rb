# =================================
# VectorFlow Services Compliance Controls
# =================================

control 'svc-01' do
  impact 0.7
  title 'Fail2ban should be running'
  desc 'Fail2ban provides intrusion prevention'

  describe service('fail2ban') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'svc-02' do
  impact 0.5
  title 'Auditd should be running'
  desc 'Auditd provides security auditing capabilities'

  describe service('auditd') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'svc-03' do
  impact 0.5
  title 'Chrony should be running for time sync'
  desc 'Time synchronization is important for log correlation'

  describe.one do
    describe service('chrony') do
      it { should be_enabled }
      it { should be_running }
    end
    describe service('chronyd') do
      it { should be_enabled }
      it { should be_running }
    end
  end
end

control 'svc-04' do
  impact 1.0
  title 'SSH service should be running'
  desc 'SSH is required for remote access'

  describe.one do
    describe service('ssh') do
      it { should be_enabled }
      it { should be_running }
    end
    describe service('sshd') do
      it { should be_enabled }
      it { should be_running }
    end
  end
end
