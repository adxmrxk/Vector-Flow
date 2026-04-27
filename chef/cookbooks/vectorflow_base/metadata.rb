name 'vectorflow_base'
maintainer 'VectorFlow Team'
maintainer_email 'team@vectorflow.local'
license 'MIT'
description 'Base configuration for VectorFlow servers'
version '1.0.0'
chef_version '>= 16.0'

supports 'ubuntu', '>= 20.04'
supports 'debian', '>= 10'
supports 'centos', '>= 8'
supports 'amazon', '>= 2'

depends 'apt', '~> 7.0'
depends 'yum', '~> 7.0'
depends 'ntp', '~> 5.0'

issues_url 'https://github.com/vectorflow/vectorflow/issues'
source_url 'https://github.com/vectorflow/vectorflow'
