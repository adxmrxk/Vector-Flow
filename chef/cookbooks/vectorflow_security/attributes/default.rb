# =================================
# VectorFlow Security Attributes
# =================================

# SSH configuration
default['vectorflow']['security']['ssh'] = {
  'port' => 22,
  'permit_root_login' => 'no',
  'password_authentication' => 'no',
  'pubkey_authentication' => 'yes',
  'x11_forwarding' => 'no',
  'max_auth_tries' => 3,
  'client_alive_interval' => 300,
  'client_alive_count_max' => 2,
  'allow_users' => ['vectorflow'],
  'allow_groups' => ['vectorflow', 'sudo'],
}

# Firewall configuration
default['vectorflow']['security']['firewall'] = {
  'enabled' => true,
  'default_policy' => 'deny',
  'allowed_ports' => {
    'ssh' => 22,
    'http' => 80,
    'https' => 443,
    'gateway' => 8080,
    'worker' => 8081,
    'inference' => 8082,
    'frontend' => 3000,
    'kubernetes_api' => 6443,
    'node_port_range' => '30000:32767',
  },
}

# Fail2ban configuration
default['vectorflow']['security']['fail2ban'] = {
  'enabled' => true,
  'bantime' => '1h',
  'findtime' => '10m',
  'maxretry' => 5,
}

# Audit logging
default['vectorflow']['security']['auditd'] = {
  'enabled' => true,
  'log_file' => '/var/log/audit/audit.log',
  'max_log_file' => 50,
  'num_logs' => 5,
}

# Security packages
default['vectorflow']['security']['packages'] = %w[
  fail2ban
  ufw
  auditd
  audispd-plugins
  rkhunter
  chkrootkit
  clamav
  clamav-daemon
]

# Automatic security updates
default['vectorflow']['security']['auto_updates'] = {
  'enabled' => true,
  'security_only' => true,
  'reboot_if_needed' => false,
}

# Compliance standards to check
default['vectorflow']['security']['compliance'] = {
  'cis_benchmark' => true,
  'check_interval' => 'daily',
}
