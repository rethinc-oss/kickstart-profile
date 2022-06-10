define puppet_profiles::nginx::intern::vhost_base (
  String $vhost                           = $title,
  Array[String] $servernames              = undef,
  Boolean $https                          = undef,
  Optional[String] $https_certificate     = undef,
  Optional[String] $https_certificate_key = undef,
  Integer $port                           = undef,
  Optional[String] $webroot               = undef,
  Optional[String] $redirect_target       = undef,
  String $access_log                      = undef,
  String $error_log                       = undef,
  String $max_body_size                   = undef,
){
  if $webroot == undef and $redirect_target == undef {
    fail('You must specify either a webroot or a redirect target for the vhost.')
  }
  if $webroot != undef and $redirect_target != undef {
    fail('You munst not specify both a webroot and a redirect target for the vhost.')
  }

  nginx::resource::server{ $vhost:
    use_default_location      => false,
    server_name               => $servernames,
    listen_port               => $port,
    listen_options            => '',
    ipv6_enable               => true,
    ipv6_listen_port          => $port,
    ipv6_listen_options       => '',
    http2                     => $https ? { true => 'on', false => 'off' }, # lint:ignore:selector_inside_resource
    index_files               => [],
    autoindex                 => 'off',
    access_log                => $access_log,
    error_log                 => $error_log,
    www_root                  => $webroot,

    ssl                       => $https,
    ssl_port                  => $https ? { true => $port, false => undef }, # lint:ignore:selector_inside_resource
    ssl_cert                  => $https_certificate,
    ssl_key                   => $https_certificate_key,
    ssl_session_timeout       => '1d',
    ssl_cache                 => "shared:SSL-${vhost}:50m",
    ssl_session_tickets       => 'off',
    ssl_dhparam               => $::puppet_profiles::nginx::_dhparam_file,

    # modern configuration. tweak to your needs.
    ssl_protocols             => 'TLSv1.2 TLSv1.3',
    ssl_ciphers               => 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256',
    ssl_prefer_server_ciphers => 'on',

    # HSTS (ngx_http_headers_module is required) (15768000 seconds = 6 months)
    add_header                => $https ? { # lint:ignore:selector_inside_resource
      true  => { 'Strict-Transport-Security' => 'max-age=15768000' },
      false => undef,
    },

    client_max_body_size      => $max_body_size,

    server_cfg_prepend        => {
      'server_tokens' => 'off',
      'include'       => $webroot != undef ? { # lint:ignore:selector_inside_resource
        true  => ['/etc/nginx/bots.d/blockbots.conf', '/etc/nginx/bots.d/ddos.conf'],
        false => undef,
      },
    },
  }

  if $redirect_target != undef {
    if !$https {
      nginx::resource::location{ "${vhost}-acme-location":
        ensure      => present,
        server      => $vhost,
        priority    => 501,
        ssl         => $https,
        ssl_only    => $https,
        location    => '/.well-known/acme-challenge/',
        www_root    => '/var/www/acme',
        index_files => [],
        raw_append  => [
          'break;',
        ]
      }
    }

    nginx::resource::location{ "${vhost}-redirect-location":
      ensure              => present,
      server              => $vhost,
      priority            => 502,
      ssl                 => $https,
      ssl_only            => $https,
      location            => '/',
      index_files         => [],
      location_cfg_append => {
        return => $redirect_target,
      },
    }
  }
}
