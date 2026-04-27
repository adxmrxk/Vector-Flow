# =================================
# VectorFlow Base Attributes
# =================================

# System configuration
default['vectorflow']['base']['timezone'] = 'UTC'
default['vectorflow']['base']['locale'] = 'en_US.UTF-8'

# User configuration
default['vectorflow']['base']['user'] = 'vectorflow'
default['vectorflow']['base']['group'] = 'vectorflow'
default['vectorflow']['base']['home'] = '/home/vectorflow'
default['vectorflow']['base']['shell'] = '/bin/bash'

# Directory structure
default['vectorflow']['base']['app_dir'] = '/opt/vectorflow'
default['vectorflow']['base']['log_dir'] = '/var/log/vectorflow'
default['vectorflow']['base']['data_dir'] = '/var/lib/vectorflow'
default['vectorflow']['base']['config_dir'] = '/etc/vectorflow'

# System packages
default['vectorflow']['base']['packages'] = %w[
  curl
  wget
  git
  vim
  htop
  jq
  unzip
  ca-certificates
  gnupg
  lsb-release
  software-properties-common
  apt-transport-https
]

# Sysctl settings for performance
default['vectorflow']['base']['sysctl'] = {
  'vm.swappiness' => 10,
  'vm.max_map_count' => 262144,
  'net.core.somaxconn' => 65535,
  'net.ipv4.tcp_max_syn_backlog' => 65535,
  'net.ipv4.ip_local_port_range' => '1024 65535',
  'net.ipv4.tcp_tw_reuse' => 1,
  'fs.file-max' => 2097152,
  'fs.inotify.max_user_watches' => 524288,
}

# File limits
default['vectorflow']['base']['limits'] = {
  'nofile' => {
    'soft' => 65536,
    'hard' => 65536,
  },
  'nproc' => {
    'soft' => 65536,
    'hard' => 65536,
  },
}

# NTP servers
default['vectorflow']['base']['ntp_servers'] = %w[
  0.pool.ntp.org
  1.pool.ntp.org
  2.pool.ntp.org
  3.pool.ntp.org
]
