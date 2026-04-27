# =================================
# VectorFlow Firewall Compliance Controls
# =================================

control 'firewall-01' do
  impact 1.0
  title 'UFW firewall should be enabled'
  desc 'The firewall should be active to protect the system'

  only_if { os.debian? }

  describe command('ufw status') do
    its('stdout') { should match(/Status: active/) }
  end
end

control 'firewall-02' do
  impact 0.7
  title 'Default incoming policy should be deny'
  desc 'Default policy should deny all incoming connections'

  only_if { os.debian? }

  describe command('ufw status verbose') do
    its('stdout') { should match(/Default: deny \(incoming\)/) }
  end
end

control 'firewall-03' do
  impact 0.5
  title 'Only required ports should be open'
  desc 'Verify that only VectorFlow required ports are accessible'

  only_if { os.debian? }

  # SSH should be allowed
  describe port(22) do
    it { should be_listening }
  end

  # VectorFlow services
  %w[8080 8081 8082 3000].each do |p|
    describe command("ufw status | grep #{p}") do
      its('stdout') { should match(/ALLOW/) }
    end
  end
end
