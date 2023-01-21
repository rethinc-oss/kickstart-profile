define puppet_profiles::nginx::vhost::grav (
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
  $_php_modules = union($php_modules, ['curl', 'gd', 'mbstring', 'xml', 'zip'])

  #############################################################################
  ### Create a base vhost & amend it with the grav specific config
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

  # Deny all direct access for these folders
  nginx::resource::location { "${_vhost_name_main}-block-system-folders":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 515,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '~* /(\.git|cache|bin|logs|backup|tests)/.*$',
    index_files         => [],
    location_cfg_append => {
      return     => '403',
      error_page => '403 /403_error.html',
    },
  }

  # Deny running scripts inside core system folders
  nginx::resource::location { "${_vhost_name_main}-block-exec-system":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 516,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '~* /(system|vendor)/.*\.(txt|xml|md|html|json|yaml|yml|php|pl|py|cgi|twig|sh|bat)$',
    index_files         => [],
    location_cfg_append => {
      return     => '403',
      error_page => '403 /403_error.html',
    },
  }

  # Deny running scripts inside user folder
  nginx::resource::location { "${_vhost_name_main}-block-exec-user":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 517,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '~* /user/.*\.(txt|md|json|yaml|yml|php|pl|py|cgi|twig|sh|bat)$',
    index_files         => [],
    location_cfg_append => {
      return     => '403',
      error_page => '403 /403_error.html',
    },
  }

  # Deny access to specific files in the root folder
  nginx::resource::location { "${_vhost_name_main}-block-system-files":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 518,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '~ /(LICENSE\.txt|composer\.lock|composer\.json|nginx\.conf|web\.config|htaccess\.txt|\.htaccess)',
    index_files         => [],
    location_cfg_append => {
      return     => '403',
      error_page => '403 /403_error.html',
    },
  }
}
