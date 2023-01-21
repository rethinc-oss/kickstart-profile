define puppet_profiles::nginx::vhost::laravel (
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
  String $webroot_dir                 = "${website_dir}/public",
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

  $_vhost_name_main = "${priority}-${domain}"
  $_php_modules = union($php_modules, ['xml', 'curl'])

  #############################################################################
  ### Create a base vhost & amend it with the laravel specific config
  #############################################################################

  puppet_profiles::nginx::vhost::phpfpm { $title:
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
    php_version         => $php_version,
    php_modules         => $_php_modules,
    php_development     => $php_development,
    php_memory_limit    => $php_memory_limit,
    php_upload_limit    => $php_upload_limit,
    php_execution_limit => $php_execution_limit,
    php_location_match  => $php_location_match,
    php_env_vars        => $php_env_vars,
  }

  nginx::resource::location { "${_vhost_name_main}-index-frontend":
    ensure      => present,
    server      => $_vhost_name_main,
    priority    => 510,
    ssl         => $https,
    ssl_only    => $https,
    location    => '= /',
    index_files => ['index.php'],
  }

  #try to get file directly, try it as a directory or fall back to php
  nginx::resource::location { "${_vhost_name_main}-try-files":
    ensure      => present,
    server      => $_vhost_name_main,
    priority    => 512,
    ssl         => $https,
    ssl_only    => $https,
    location    => '/',
    index_files => [],
    try_files   => ['$uri', '$uri/', '/index.php?$query_string'],
  }

  cron { "${domain}-laravel-scheduler":
    command => "cd ${website_dir} && php artisan schedule:run >> /dev/null 2>&1",
    user    => $user,
  }
}
