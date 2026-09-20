# InSpec tests for the `docker` Test Kitchen suite.
# Run list: vectorflow_base::default, vectorflow_docker::default
#
# base's own state is covered by the base suite; this suite only asserts
# what vectorflow_docker's recipes add.

title 'vectorflow_docker'

control 'docker-install-01' do
  impact 1.0
  title 'Docker Engine is installed, enabled and running'
  desc 'install.rb installs docker-ce and enables/starts the docker service'

  describe package('docker-ce') do
    it { should be_installed }
  end

  describe service('docker') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'docker-install-02' do
  impact 0.7
  title 'The vectorflow user is a member of the docker group'
  desc 'install.rb adds base/user to the docker group so it can run docker without sudo'

  describe user('vectorflow') do
    it { should exist }
    its('groups') { should include 'docker' }
  end
end

control 'docker-configure-01' do
  impact 0.8
  title 'Docker daemon.json matches the configured daemon settings'
  desc 'configure.rb renders docker/daemon as JSON to /etc/docker/daemon.json'

  describe file('/etc/docker/daemon.json') do
    it { should exist }
    its('mode') { should cmp '0644' }
  end

  describe json('/etc/docker/daemon.json') do
    its(['log-driver']) { should eq 'json-file' }
    its(['storage-driver']) { should eq 'overlay2' }
    its(['live-restore']) { should eq true }
    its(['userland-proxy']) { should eq false }
    its(['insecure-registries']) { should include 'localhost:5000' }
  end
end

control 'docker-configure-02' do
  impact 0.5
  title 'A systemd drop-in overrides the docker unit'
  desc 'configure.rb templates a docker.service.d override.conf and reloads systemd'

  describe file('/etc/systemd/system/docker.service.d/override.conf') do
    it { should exist }
  end
end

control 'docker-configure-03' do
  impact 0.4
  title 'A weekly docker system prune cron job is scheduled'
  desc 'configure.rb schedules `docker system prune` via cron for docker/prune_schedule'

  describe cron do
    with(user: 'root')
    its('commands') { should include(match(/docker system prune -af/)) }
  end
end

control 'docker-compose-01' do
  impact 0.8
  title 'Docker Compose v2 plugin is installed and callable'
  desc 'compose.rb installs the compose CLI plugin and symlinks docker-compose'

  describe file('/usr/local/lib/docker/cli-plugins/docker-compose') do
    it { should exist }
    it { should be_executable }
  end

  describe file('/usr/local/bin/docker-compose') do
    it { should be_symlink }
  end

  describe command('docker compose version') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/2\.24\.0/) }
  end
end

control 'docker-networks-01' do
  impact 0.6
  title 'The vectorflow-net bridge network exists with the configured subnet'
  desc 'networks.rb creates one docker network per entry in docker/networks'

  describe command('docker network inspect vectorflow-net --format "{{(index .IPAM.Config 0).Subnet}}"') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(%r{172\.28\.0\.0/16}) }
  end
end
