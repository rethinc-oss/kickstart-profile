define puppet_profiles::phpfpm::instance (
){
  if !defined(Class['puppet_profiles::phpfpm']) {
    fail('You must include the phpfpm profile before declaring phpfpm instances.')
  }

  if $title =~ /(\d\.\d)/ {
    $_php_version = "${1}"
    $_php_package = "php${_php_version}-fpm"
  } else {
    fail { "Mailformed title: ${title}": }
  }

  $_default_pool = "/etc/php/${_php_version}/fpm/pool.d/www.conf"

  ensure_packages([$_php_package])

  file { $_default_pool:
    ensure  => absent,
    require => Package[$_php_package],
  }

  systemd::dropin_file { "${_php_package}-dropin":
    unit     => "${_php_package}.service",
    filename => 'local.conf',
    content  => epp('puppet_profiles/phpfpm/systemd.dropin.epp',
      {
        php_version => $_php_version,
      }
    ),
    require  => [Package[$_php_package], File[$_default_pool]],
  }
  # Workaround, becausse the dropin doesn't trigger a daemon-reload automatically.
  # See: https://github.com/voxpupuli/puppet-systemd/issues/234
  #      https://github.com/voxpupuli/puppet-systemd/pull/237
  ~> exec { 'systemctl-daemon-reload':
    command     => '/bin/systemctl daemon-reload',
    path        => $facts['path'],
    refreshonly => true,
  }
  ~> service { $_php_package:
    ensure => 'running',
    enable => true,
  }
}
