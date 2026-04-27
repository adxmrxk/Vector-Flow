name 'vectorflow_docker'
maintainer 'VectorFlow Team'
maintainer_email 'team@vectorflow.local'
license 'MIT'
description 'Docker installation and configuration for VectorFlow'
version '1.0.0'
chef_version '>= 16.0'

supports 'ubuntu', '>= 20.04'
supports 'debian', '>= 10'
supports 'centos', '>= 8'
supports 'amazon', '>= 2'

depends 'vectorflow_base', '~> 1.0'

issues_url 'https://github.com/vectorflow/vectorflow/issues'
source_url 'https://github.com/vectorflow/vectorflow'
