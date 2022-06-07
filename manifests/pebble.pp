# @summary Installs and configures a local ACME Server
#
# This profile manages Pebble, a small ACME test server intended as a
# local development Certificate Authority. Do not use this in
# production!
#
# @example
#   include puppet_profiles::pebble
#
class puppet_profiles::pebble (
  String $pebble_version,
){
  include ::stdlib

  ensure_packages(['golang'])

  exec { 'create_pebble_source_dir':
    command => '/usr/bin/mkdir -p /opt/go/src/github.com/letsencrypt/',
    creates => '/opt/go/src/github.com/letsencrypt/',
    onlyif  => '/usr/bin/test ! -d /opt/go/src/github.com/letsencrypt/',
    require => [ Package['golang'] ],
  }

  exec { 'clone_pebble_repo':
    command => '/usr/bin/git clone https://github.com/letsencrypt/pebble.git',
    cwd     => '/opt/go/src/github.com/letsencrypt/',
    creates => '/opt/go/src/github.com/letsencrypt/pebble/',
    onlyif  => '/usr/bin/test ! -d /opt/go/src/github.com/letsencrypt/pebble/.git',
    require => [ Exec['create_pebble_source_dir'] ],
  }

  exec { 'fetch_pebble_repo':
    command => '/usr/bin/git fetch',
    cwd     => '/opt/go/src/github.com/letsencrypt/pebble/',
    onlyif  => "/usr/bin/test -d /opt/go/src/github.com/letsencrypt/pebble/.git -a $(/usr/bin/git describe --tags) != '${pebble_version}'",
    require => [ Exec['clone_pebble_repo'] ],
  }

  exec { 'checkout_pebble_version':
    command => "/usr/bin/git checkout -f ${pebble_version} && rm -f /opt/go/bin/pebble && rm -f /opt/go/bin/pebble-challtestsrv",
    cwd     => '/opt/go/src/github.com/letsencrypt/pebble/',
    onlyif  => "/usr/bin/test $(/usr/bin/git describe --tags) != '${pebble_version}'",
    require => [ Exec['fetch_pebble_repo'] ],
  }

  exec { 'install_pebble':
    command     => '/usr/bin/go install -mod=readonly ./...',
    environment => ['GOPATH=/opt/go', 'GOCACHE=/opt/go/cache'],
    cwd         => '/opt/go/src/github.com/letsencrypt/pebble/',
    onlyif      => '/usr/bin/test ! -f /opt/go/bin/pebble',
    creates     => '/opt/go/bin/pebble',
    require     => [ Package['golang'], Exec['checkout_pebble_version'] ],
    notify      => Service['pebble']
  }

  file { '/opt/pebble':
    ensure  => directory,
    recurse => true,
  }

  file { '/opt/pebble/config.json':
    ensure  => present,
    content => epp('puppet_profiles/pebble/config.json.epp'),
    require => [ File['/opt/pebble']],
  }

  file { '/opt/pebble/cert.pem':
    ensure  => present,
    content => epp('puppet_profiles/pebble/cert.pem.epp'),
    require => [ File['/opt/pebble']],
  }

  file { '/opt/pebble/key.pem':
    ensure  => present,
    content => epp('puppet_profiles/pebble/key.pem.epp'),
    require => [ File['/opt/pebble']],
  }

  file { '/opt/pebble/minica.pem':
    ensure  => present,
    content => epp('puppet_profiles/pebble/minica.pem.epp'),
    require => [ File['/opt/pebble']],
  }

  file { '/usr/lib/systemd/system/pebble.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('puppet_profiles/pebble/pebble.service.epp'),
    require => [
      File['/opt/pebble/config.json'],
      File['/opt/pebble/cert.pem'],
      File['/opt/pebble/key.pem'],
      File['/opt/pebble/minica.pem'],
      Exec['install_pebble']
    ],
  }
  ~> service {'pebble':
    ensure => 'running',
  }

  exec { 'install_system_cert':
    command => '/usr/bin/openssl x509 -in /opt/pebble/minica.pem -inform PEM -out /usr/local/share/ca-certificates/minica.crt',
    creates => '/usr/local/share/ca-certificates/minica.crt',
    require => [ File['/opt/pebble/minica.pem'] ],
  }
  -> exec { 'update_system_certs':
    command => '/usr/sbin/update-ca-certificates',
  }
}
