# define: profile::server::nginx::website::static
#
# This definition creates a virtual host
#
# Parameters:
#   [*domain*]                     - The base domain of the virtual host (e.g. 'example.com')
#   [*domain_www*]                 - BOOL value to enable/disable creating a virtual host for "www.${domain}"; default: true
#   [*domain_primary*]             - Which domain to redirect to (base|www), if $domain_www is enabled; default: www
#   [*https*]                      - BOOL value to enable listening on port 443; default: true
#
define puppet_profiles::nginx::vhost::static (
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
  String $webroot_parent_dir          = $user_dir,
  String $webroot                     = "${webroot_parent_dir}/htdocs",
  Array[Hash] $cronjobs               = [],
){
  if !defined(Class['::puppet_profiles::nginx']) {
    fail('You must include the nginx profile before declaring a wesite.')
  }

  $_primary_domain             = ($domain_www and $domain_primary == www) ? { true => "www.${domain}", false => $domain }
  $_secondary_domain           = $domain_www ? { true => $domain_primary ? { www => $domain, base => "www.${domain}"}, false => undef }

  $_vhost_name_main            = "${priority}-${domain}"
  $_vhost_name_redirect_http   = "${_vhost_name_main}-redirect-http"
  $_vhost_name_redirect_https  = "${_vhost_name_main}-redirect-https"

  # if the primary vhost is https based, redirect from http for both the primary and secondary the domain, else just from the secondary
  # domain. if there is no secondary domain, skip it.
  $_http_redirect_servernames  = delete_undef_values( $https ? { true => [$_primary_domain, $_secondary_domain], false => [$_secondary_domain] } )

  # if there is a secondary domain and the primary vhost is https based, redirect the https based secondary domain to the primary domain.
  $_https_redirect_servernames = delete_undef_values( $https ? { true => [$_secondary_domain], false => [] } )

  $_redirect_protocol          = $https ? { true => 'https://', false => 'http://' }
  $_redirect_target            = "301 ${_redirect_protocol}${_primary_domain}\$request_uri"

  $_main_access_log            = "${log_dir}/${domain}_access.log"
  $_main_error_log             = "${log_dir}/${domain}_error.log"
  $_redirect_access_log        = "${log_dir}/${domain}_redirect_access.log"
  $_redirect_error_log         = "${log_dir}/${domain}_redirect_error.log"

  $_https_certificate          = "/etc/letsencrypt/live/${_primary_domain}/fullchain.pem"
  $_https_certificate_key      = "/etc/letsencrypt/live/${_primary_domain}/privkey.pem"

  $_configuration_reloads      = $https ? {
    true  => ["${domain}_nginx_reload_http", "${domain}_nginx_reload_https"],
    false => ["${domain}_nginx_reload_http"],
  }

  #############################################################################
  ### Create vhost user account
  #############################################################################

  puppet_profiles::nginx::intern::vhost_user { $user:
    homedir        => $user_dir,
    manage_homedir => $manage_user_dir,
    addon_group    => $user_addon_group,
    public_keys    => $user_public_keys,
    public_keydefs => $user_public_keydefs,
  }
  -> file { $webroot:
    ensure  => 'directory',
    owner   => $user,
    group   => $user,
    mode    => '0750',
    require => User[$user]
  }

  #############################################################################
  ### Create vhost nginx configuration
  #############################################################################

  ### Reload Nginx configs one (HTTP only) or two times (HTTPS)

  exec { $_configuration_reloads:
    command => '/bin/systemctl is-active --quiet nginx && /bin/systemctl reload nginx || /bin/systemctl restart nginx',
  }

  ### Redirecting HTTP-VHost

  if ( !empty($_http_redirect_servernames)) {
    puppet_profiles::nginx::intern::vhost_base{ $_vhost_name_redirect_http:
      servernames     => $_http_redirect_servernames,
      https           => false,
      port            => $http_port,
      redirect_target => $_redirect_target,
      access_log      => $_redirect_access_log,
      error_log       => $_redirect_error_log,
      max_body_size   => '1M',
    }

    Puppet_profiles::Nginx::Intern::Vhost_base[$_vhost_name_redirect_http] -> Exec[$_configuration_reloads[0]]
  } else {
    nginx::resource::server{ $_vhost_name_redirect_http:
      ensure => absent,
    }
  }

  ### Redirecting HTTPS-VHost

  if ( $https and !empty($_https_redirect_servernames) ) {
    puppet_profiles::nginx::intern::vhost_base{ $_vhost_name_redirect_https:
      servernames           => $_https_redirect_servernames,
      https                 => true,
      https_certificate     => $_https_certificate,
      https_certificate_key => $_https_certificate_key,
      port                  => $https_port,
      redirect_target       => $_redirect_target,
      access_log            => $_redirect_access_log,
      error_log             => $_redirect_error_log,
      max_body_size         => '1M',
    }

    Letsencrypt::Certonly[$domain] -> Puppet_profiles::Nginx::Intern::Vhost_base[$_vhost_name_redirect_https] -> Exec[$_configuration_reloads[1]]
  } else {
    nginx::resource::server{ $_vhost_name_redirect_https:
      ensure => absent,
    }
  }

  ### Main  HTTP(S)-VHost

  puppet_profiles::nginx::intern::vhost_base{ $_vhost_name_main:
    servernames           => [$_primary_domain],
    https                 => $https,
    https_certificate     => $_https_certificate,
    https_certificate_key => $_https_certificate_key,
    port                  => $https ? { true => $https_port, false => $http_port }, # lint:ignore:selector_inside_resource
    webroot               => $webroot,
    access_log            => $_main_access_log,
    error_log             => $_main_error_log,
    max_body_size         => $max_body_size,
  }

  if $https {
    Letsencrypt::Certonly[$domain] -> Puppet_profiles::Nginx::Intern::Vhost_base[$_vhost_name_main] -> Exec[$_configuration_reloads[1]]
  } else {
    Puppet_profiles::Nginx::Intern::Vhost_base[$_vhost_name_main] -> Exec[$_configuration_reloads[0]]
  }

  # Deny all attempts to access hidden files such as .git, .DS_Store et al.
  # Keep logging the requests to parse later (or to pass to firewall utilities such as fail2ban)
  nginx::resource::location { "${_vhost_name_main}-block-hidden":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 501,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '~ /\.',
    index_files         => [],
    location_cfg_append => {
      return     => '403',
      error_page => '403 /403_error.html',
    },
  }

  # Don't polute logs with messages about /favicon.ico
  nginx::resource::location { "${_vhost_name_main}-favicon":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 502,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '/favicon.ico',
    index_files         => [],
    location_cfg_append => {
      log_not_found => 'off',
      access_log    => 'off',
    },
  }

  # Don't polute logs with messages about /robots.txt
  nginx::resource::location { "${_vhost_name_main}-robots":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 503,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '/robots.txt',
    index_files         => [],
    location_cfg_append => {
      log_not_found => 'off',
      access_log    => 'off',
    },
  }

  # Don't polute logs with messages about /apple-touch-icon-precomposed.png
  nginx::resource::location { "${_vhost_name_main}-apple-touch-icon1":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 504,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '/apple-touch-icon-precomposed.png',
    index_files         => [],
    location_cfg_append => {
      log_not_found => 'off',
      access_log    => 'off',
    },
  }

  # Don't polute logs with messages about /apple-touch-icon.png
  nginx::resource::location { "${_vhost_name_main}-apple-touch-icon2":
    ensure              => present,
    server              => $_vhost_name_main,
    priority            => 505,
    ssl                 => $https,
    ssl_only            => $https,
    location            => '/apple-touch-icon.png',
    index_files         => [],
    location_cfg_append => {
      log_not_found => 'off',
      access_log    => 'off',
    },
  }

  #############################################################################
  ### Create Letsencrypt certificate for the vhost
  #############################################################################

  if ( $https ) {
    letsencrypt::certonly { $domain:
      domains              => delete_undef_values( [$_primary_domain, $_secondary_domain] ),
      plugin               => 'webroot',
      webroot_paths        => ['/var/www/acme'],
      deploy_hook_commands => ['/bin/systemctl reload nginx.service'],
    }

    Exec[$_configuration_reloads[0]] -> Letsencrypt::Certonly[$domain]
  }

  #############################################################################
  ### Declare vhost specific cronjobs
  #############################################################################

  $cronjobs.each |$cronjob| {
    $_command = "${user_dir}/cronjobs/${cronjob['name']}"

    file { $_command:
      owner => $user,
      group => $user,
      mode  => '0700',
    }
    -> cron { "${domain}-${cronjob['name']}":
      *       => $cronjob,
      command => $_command,
      user    => $user,
    }
  }
}
