# InSpec tests for the `full-stack` Test Kitchen suite.
# Run list: vectorflow_base, vectorflow_docker, vectorflow_kubernetes,
#           vectorflow_security, vectorflow_app
# Suite attribute overrides: kubernetes.node_type = standalone,
#                             security.firewall.enabled = false
#
# base/docker/security fundamentals are already covered by their own
# suites; this suite asserts the kubernetes tooling and the app layer that
# only exist when every cookbook runs together. Note that vectorflow_app's
# `kubectl apply` / `create-namespace` / `create-configmap` executes are all
# guarded by `only_if 'kubectl cluster-info'` in the recipes, and this suite
# has no real cluster (node_type=standalone only installs the minikube
# binary, it does not start a cluster) — so those resources are expected to
# no-op, and the tests below don't assert cluster state.

title 'vectorflow_full_stack'

control 'full-stack-kubetools-01' do
  impact 0.8
  title 'kubectl, helm and minikube CLIs are installed'
  desc 'kubectl.rb, helm.rb and minikube.rb each install their binary to /usr/local/bin'

  describe file('/usr/local/bin/kubectl') do
    it { should exist }
    it { should be_executable }
  end

  describe file('/usr/local/bin/helm') do
    it { should exist }
    it { should be_executable }
  end

  describe file('/usr/local/bin/minikube') do
    it { should exist }
    it { should be_executable }
  end
end

control 'full-stack-kubetools-02' do
  impact 0.4
  title 'kubectl config directory and aliases exist for the vectorflow user'
  desc 'kubectl.rb creates ~/.kube and ~/.kubectl_aliases for base/user'

  describe directory('/home/vectorflow/.kube') do
    it { should exist }
    it { should be_owned_by 'vectorflow' }
    its('mode') { should cmp '0700' }
  end

  describe file('/home/vectorflow/.kubectl_aliases') do
    it { should exist }
  end
end

control 'full-stack-app-config-01' do
  impact 1.0
  title 'The rendered vectorflow.yaml reflects the configured services and model'
  desc 'config.rb templates vectorflow.yaml from app/services, app/model, app/pinecone'

  describe file('/etc/vectorflow/vectorflow.yaml') do
    it { should exist }
    its('mode') { should cmp '0640' }
    its('content') { should match(/all-MiniLM-L6-v2/) }
    its('content') { should match(/us-east-1/) }
    its('content') { should match(/vectorflow-index/) }
  end
end

control 'full-stack-app-config-02' do
  impact 0.9
  title 'The rendered environment file is marked sensitive and not world-readable'
  desc 'config.rb templates vectorflow.env with sensitive true and mode 0640'

  describe file('/etc/vectorflow/vectorflow.env') do
    it { should exist }
    its('mode') { should cmp '0640' }
    it { should_not be_readable.by('other') }
  end
end

control 'full-stack-app-deploy-01' do
  impact 0.7
  title 'A Kubernetes deployment manifest is rendered per enabled service'
  desc 'deploy.rb templates one k8s-<service>.yaml per enabled entry in app/services'

  %w(gateway worker inference frontend).each do |svc|
    describe file("/etc/vectorflow/k8s-#{svc}.yaml") do
      it { should exist }
      its('content') { should match(/vectorflow-#{svc}/) }
    end
  end
end

control 'full-stack-app-monitoring-01' do
  impact 0.7
  title 'Health-check and status scripts are installed and scheduled'
  desc 'monitoring.rb templates the health-check/status scripts and a cron schedule'

  describe file('/usr/local/bin/vectorflow-health-check') do
    it { should exist }
    it { should be_executable }
  end

  describe file('/usr/local/bin/vectorflow-status') do
    it { should exist }
    it { should be_executable }
  end

  describe file('/etc/vectorflow/prometheus-targets.yaml') do
    it { should exist }
    its('content') { should match(/8080/) }
  end

  describe cron do
    with(user: 'root')
    its('commands') { should include(match(/vectorflow-health-check/)) }
  end
end

control 'full-stack-app-monitoring-02' do
  impact 0.4
  title 'The monitoring log directory exists and is owned by the service account'
  desc 'monitoring.rb creates log_dir/monitoring owned by base/user'

  describe directory('/var/log/vectorflow/monitoring') do
    it { should exist }
    it { should be_owned_by 'vectorflow' }
  end
end

control 'full-stack-docker-01' do
  impact 0.6
  title 'Docker still comes up correctly alongside the rest of the stack'
  desc 'vectorflow_docker::install still enables and starts docker in the combined run list'

  describe service('docker') do
    it { should be_enabled }
    it { should be_running }
  end
end
