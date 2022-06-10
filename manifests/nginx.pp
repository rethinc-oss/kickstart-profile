# A description of what this class does
#
# @summary A short summary of the purpose of this class
#
# @example
#   include profile::server::nginx
class puppet_profiles::nginx (
  String  $acme_server,
  String  $acme_email,
  Boolean $generate_dhparams,
){
  include ::stdlib

  class {'::nginx':
    server_purge           => true,
    package_source         => 'nginx-stable',
    nginx_version          => pick(fact('nginx_version'), '1.15.0'),
    # High values for the bad bot blocker list,
    # taken from the botblocker configuration
    names_hash_bucket_size => 256,
    names_hash_max_size    => 4096,
  }

  $_default_fqdn        = 'default.vhost'
  $_default_cert        = "/etc/nginx/${_default_fqdn}.crt"
  $_default_key         = "/etc/nginx/${_default_fqdn}.key"
  $_default_log         = "/var/log/nginx/${_default_fqdn}.log"
  $_dist_vhost_files    = ['/etc/nginx/sites-enabled/default', '/etc/nginx/sites-available/default', '/etc/nginx/conf.d/default.conf']
  $_dhparam_file        = $generate_dhparams ? { true => '/etc/ssl/certs/dhparam4096.pem', false => undef }
  $_ips                 = $facts['networking']['interfaces'].reduce([]) |$memo, $value| {
    $a = $memo + $value[1]['ip'] +  $value[1]['ip6']
    delete_undef_values($a)
  }

  file{ $_dist_vhost_files:
    ensure => 'absent',
  }

  if $generate_dhparams {
    exec { 'generate_dhparams':
      command => "/usr/bin/openssl dhparam -outform PEM -out ${_dhparam_file} 4096",
      timeout => 600,
      creates => $_dhparam_file,
      require => Package['nginx'],
    }
    -> file{ $_dhparam_file:
      ensure => 'file',
      owner  => $nginx::params::daemon_user,
      group  => $nginx::params::daemon_user,
      mode   => '0600',
    }
  }

  exec { 'generate_default_sslcert':
    command => "/usr/bin/openssl req -newkey rsa:2048 -nodes -keyout ${_default_key} -x509 -days 3650 -out ${_default_cert} -subj '/CN=${_default_fqdn}'",
    creates => [$_default_key, $_default_cert],
    require => Package['nginx'],
  }
  -> file{ $_default_key:
    ensure => 'file',
    owner  => $nginx::params::daemon_user,
    group  => $nginx::params::daemon_user,
    mode   => '0600',
  }
  -> file{ $_default_cert:
    ensure => 'file',
    owner  => $nginx::params::daemon_user,
    group  => $nginx::params::daemon_user,
    mode   => '0600',
  }

  @user { $nginx::params::daemon_user:
    gid        => $nginx::params::daemon_user,
    groups     => [],
    membership => inclusive,
  }
  User <| title == $nginx::params::daemon_user |>

  nginx::resource::server{ '000-default_http':
    use_default_location => false,
    server_name          => [ '_' ],
    listen_options       => 'default_server',
    ipv6_listen_options  => 'default_server',
    ipv6_enable          => true,
    http2                => 'on',
    index_files          => [],
    autoindex            => 'off',
    access_log           => $_default_log,
    error_log            => $_default_log,
    server_cfg_append    => {
      return => '444',
    },
    require              => [ File[$_dist_vhost_files] ],
  }

  nginx::resource::server{ '000-default_https':
    use_default_location      => false,
    server_name               => [ '_' ],
    listen_port               => 443,
    listen_options            => 'default_server',
    ipv6_enable               => true,
    ipv6_listen_port          => 443,
    ipv6_listen_options       => 'default_server',
    http2                     => 'on',
    index_files               => [],
    autoindex                 => 'off',
    access_log                => $_default_log,
    error_log                 => $_default_log,

    ssl                       => true,
    ssl_port                  => 443,
    ssl_cert                  => $_default_cert,
    ssl_key                   => $_default_key,
    ssl_session_timeout       => '1d',
    ssl_cache                 => 'shared:SSL-default:5m',
    ssl_session_tickets       => 'off',
    ssl_dhparam               => $_dhparam_file,

    # modern configuration. tweak to your needs.
    ssl_protocols             => 'TLSv1.2 TLSv1.3',
    ssl_ciphers               => 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256',
    ssl_prefer_server_ciphers => 'on',

    # HSTS (ngx_http_headers_module is required) (15768000 seconds = 6 months)
    add_header                => {
      'Strict-Transport-Security' => 'max-age=15768000',
      'X-Frame-Options'           => 'DENY',
    },

    # OCSP Stapling ---
    # fetch OCSP records from URL in ssl_certificate and cache them
    # disable for default vhost. Reason: self signed certificate
    ssl_stapling              => false,
    ssl_stapling_verify       => false,

    server_cfg_append         => {
      return => '444',
    },
    require                   => [ File[$_dist_vhost_files], Exec['generate_default_sslcert'] ] + ($generate_dhparams ? { true => Exec['generate_dhparams'], false => [] }),
  }

  #############################################################################
  ### Install NgxBotblocker
  #############################################################################

  ### Install files

  file { '/etc/nginx/bots.d/':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  [
    'install-ngxblocker',
    'setup-ngxblocker',
    'update-ngxblocker'
  ].each |$file| {
    file { "/usr/local/sbin/${file}":
      owner   => 'root',
      group   => 'root',
      mode    => '0700',
      content => epp("puppet_profiles/nginx/botblocker/scripts/${file}.epp"),
      replace => false,
    }
  }

  [
    'botblocker-nginx-settings.conf',
    'globalblacklist.conf'
  ].each |$file| {
    file { "/etc/nginx/conf.d/${file}":
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      content => epp("puppet_profiles/nginx/botblocker/conf.d/${file}.epp"),
      replace => false,
    }
  }

  [
    'bad-referrer-words.conf',
    'blacklist-ips.conf',
    'blacklist-user-agents.conf',
    'blockbots.conf',
    'custom-bad-referrers.conf',
    'ddos.conf',
  ].each |$file| {
    file { "/etc/nginx/bots.d/${file}":
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      content => epp("puppet_profiles/nginx/botblocker/bots.d/${file}.epp"),
      replace => false,
      require => File['/etc/nginx/bots.d/'],
    }
  }

  ### Install dynamic files

  file { '/etc/nginx/bots.d/whitelist-ips.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => epp('puppet_profiles/nginx/botblocker/bots.d/whitelist-ips.conf.epp', { ips => $_ips }),
    require => File['/etc/nginx/bots.d/'],
  }

  concat { '/etc/nginx/bots.d/whitelist-domains.conf':
    owner => 'root',
    group => 'root',
    mode  => '0600'
  }

  concat::fragment { 'whitelist_domains_header':
    target  => '/etc/nginx/bots.d/whitelist-domains.conf',
    content => epp('puppet_profiles/nginx/botblocker/bots.d/whitelist-domains-header.conf.epp'),
    order   => '01',
  }

  concat::fragment { 'whitelist_domains_footer':
    target  => '/etc/nginx/bots.d/whitelist-domains.conf',
    content => epp('puppet_profiles/nginx/botblocker/bots.d/whitelist-domains-footer.conf.epp'),
    order   => '99',
  }

  ### Update the bot definitions

  systemd::timer { 'ngxblocker-update.timer':
    timer_content   => epp('puppet_profiles/nginx/botblocker/ngxblocker-update.timer.epp'),
    service_content => epp('puppet_profiles/nginx/botblocker/ngxblocker-update.service.epp'),
    active          => true,
    enable          => true,
  }

  #############################################################################
  ### Install Letsencrypt client
  #############################################################################

  file{ ['/var/www/', '/var/www/acme/'] :
    ensure => 'directory',
    owner  => $nginx::params::daemon_user,
    group  => $nginx::params::daemon_user,
    mode   => '0750',
  }

  class { 'letsencrypt':
    package_ensure    => 'installed',
    agree_tos         => true,
    config            => {
      email  => $acme_email,
      server => $acme_server,
    },
    cron_scripts_path => '/var/lib/letsencrypt',
    require           => [ Class['apt::update'], File['/var/www/acme/'] ],
  }
}
