define puppet_profiles::nginx::vhost::phpfpm (
  String $domain                      = $title,
  Boolean $domain_www                 = true,
  Enum['base', 'www'] $domain_primary = 'www',
  Integer $priority                   = 100,
  Boolean $https                      = true,
  Integer $http_port                  = 80,
  Integer $https_port                 = 443,
  String $log_dir                     = '/var/log/nginx/',
  String $max_body_size               = '10M',
  String $user                        = $domain,
  String $user_dir                    = "/var/www/${domain}",
  Boolean $manage_user_dir            = true,
  Optional[String] $user_addon_group  = undef,
  Optional[Array[String]] $user_public_keys = undef,
  Optional[Hash[String, Hash]] $user_public_keydefs = lookup('puppet_profiles::base::ssh_public_keys', undef, undef, undef),
  String $website_dir                 = "${user_dir}/website",
  String $webroot_dir                 = $website_dir,
  Array[Hash] $cronjobs               = [],
  String $php_version                 = undef,
  Array[String] $php_modules          = [],
  Boolean $php_development            = false,
  String $php_memory_limit            = '64M',
  String $php_upload_limit            = '10M',
  Integer $php_execution_limit        = 30,
  String $php_location_match          = '~ \.php$',
  Hash $php_env_vars                  = {},
){
  if !defined(Class['puppet_profiles::nginx']) {
    fail('You must include the nginx profile before declaring a vhost.')
  }
  if !defined(Class['puppet_profiles::phpfpm']) {
    fail('You must include the phpfpm profile before declaring a php vhsot.')
  }
  unless $php_version =~ /(\d\.\d)/ {
    fail { "Mailformed php version: ${php_version}": }
  }

  $_php_admin_values_base = {
    'memory_limit'        => $php_memory_limit,
    'upload_max_filesize' => $php_upload_limit,
    'post_max_size'       => $php_upload_limit,
    'max_execution_time'  => $php_execution_limit,
    'expose_php'          => 'Off',
    'cgi.fix_pathinfo'    => 0,
  }

  if $php_development {
    $_php_admin_values_devel = {
      'xdebug.remote_enable'       => 'true',
      'xdebug.remote_connect_back' => 'true',
      'xdebug.remote_autostart'    => 'true',
      'error_reporting'            => 'E_ALL',
      'display_errors'             => 'On',
      'display_startup_errors'     => 'On',
    }
  } else {
    $_php_admin_values_devel = {}
  }

  $_php_admin_values = $_php_admin_values_base + $_php_admin_values_devel

  $_vhost_name_main  = "${priority}-${domain}"
  $_pool_file_socket = "unix:/run/php/${domain}.sock"
  $_php_modules      = $php_modules.map |$module| { "php${php_version}-${module}" }

  #############################################################################
  ### Ensure the php version is installed & create a pool for the vhost
  #############################################################################

  ensure_resource('puppet_profiles::phpfpm::instance', $php_version, {})
  ensure_packages($_php_modules, { ensure => 'installed' })

  puppet_profiles::phpfpm::pool { $domain:
    pool_user             => $user,
    pool_group            => $user,
    pool_php_version      => $php_version,
    pool_php_env_values   => $php_env_vars,
    pool_php_admin_values => $_php_admin_values,
    require               => [
      Puppet_profiles::Nginx::Vhost::Static[$title],
    ],
  }

  #############################################################################
  ### Create a base vhost & amend it with the php specific config
  #############################################################################

  puppet_profiles::nginx::vhost::static { $title:
    domain              => $domain,
    domain_www          => $domain_www,
    domain_primary      => $domain_primary,
    priority            => $priority,
    https               => $https,
    http_port           => $http_port,
    https_port          => $https_port,
    log_dir             => $log_dir,
    max_body_size       => $php_upload_limit,
    user                => $user,
    user_dir            => $user_dir,
    manage_user_dir     => $manage_user_dir,
    user_addon_group    => $user_addon_group,
    user_public_keys    => $user_public_keys,
    user_public_keydefs => $user_public_keydefs,
    website_dir         => $website_dir,
    webroot_dir         => $webroot_dir,
    cronjobs            => $cronjobs,
  }

  nginx::resource::location { "${_vhost_name_main}-php":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 580,
    ssl                 => $https,
    ssl_only            => $https,
    location            => $php_location_match,
    index_files         => [],
    proxy               => undef,
    fastcgi             => $_pool_file_socket,
    fastcgi_script      => undef,
    location_cfg_append => {
      fastcgi_connect_timeout => '60s',
      fastcgi_read_timeout    => $php_execution_limit,
      fastcgi_send_timeout    => '60s',
      fastcgi_buffers         => '8 16k',
      fastcgi_buffer_size     => '32k',
    },
    try_files           => ['$uri', '=404'],
  }

  #############################################################################
  ### Install a local php and composer executable for the vhost user
  #############################################################################

  file { "${user_dir}/bin":
    ensure  => 'directory',
    owner   => $user,
    group   => $user,
    mode    => '0770',
    require => [
      Puppet_profiles::Nginx::Vhost::Static[$title],
    ],
  }

  file { "${user_dir}/bin/php":
    ensure  => 'link',
    target  => "/usr/bin/php${php_version}",
    owner   => $user,
    group   => $user,
    mode    => '0770',
    require => [
      Puppet_profiles::Phpfpm::Instance[$php_version],
      File["${user_dir}/bin"],
    ],
  }

  puppet_profiles::phpfpm::composer { "${user_dir}/bin/composer":
    owner   => $user,
    require => [
      Puppet_profiles::Phpfpm::Instance[$php_version],
      File["${user_dir}/bin"],
    ],
  }
}
