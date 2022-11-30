define puppet_profiles::phpfpm::composer (
  String $target_path       = $title,
  String $owner             = undef,
  String $group             = $owner,
  String $mode              = '0770',
  Optional[String] $version = undef,
  $download_timeout         = '0',
){
  $_source_url = $version ? {
    undef   => 'https://getcomposer.org/composer-stable.phar',
    default => "https://getcomposer.org/download/${version}/composer.phar"
  }

  $_unless_cmd = $version ? {
    undef   => "/usr/bin/test -f ${target_path}",
    default => "/usr/bin/test -f ${target_path} && ${target_path} -V | /usr/bin/grep -q ${version}"
  }

  ensure_packages(['curl', 'unzip'])

  exec { "composer-install-${target_path}":
    command => "/usr/bin/curl -sS -o ${target_path} ${_source_url}",
    user    => $owner,
    unless  => $_unless_cmd,
    timeout => $download_timeout,
    require => Package['curl'],
  }

  file { $target_path:
    ensure  => file,
    owner   => $owner,
    group   => $group,
    mode    => $mode,
    require => Exec["composer-install-${target_path}"],
  }
}
