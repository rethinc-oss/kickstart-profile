define puppet_profiles::phpfpm::pool (
  String $pool_name           = $title,
  String $pool_user           = $pool_name,
  String $pool_group          = $pool_name,
  String $pool_php_version    = undef,
  String $pool_conf_dir       = "/etc/php/${pool_php_version}/fpm/pool.d",
  Hash $pool_php_env_values   = {},
  Hash $pool_php_admin_values = {},
){
  unless $pool_php_version =~ /(\d\.\d)/ {
    fail { "Mailformed version in pool resource[${pool_name}]: ${pool_php_version}": }
  }

  $_pool_conf_file   = "${pool_conf_dir}/${pool_name}.conf"
  $_pool_fpm_service = "php${pool_php_version}-fpm"

  file { $_pool_conf_file:
    content => epp('puppet_profiles/phpfpm/pool.conf.epp',
      {
        name                  => $pool_name,
        user                  => $pool_user,
        group                 => $pool_group,
        pool_php_env_values   => $pool_php_env_values,
        pool_php_admin_values => $pool_php_admin_values,
      }
    ),
    require => Package[$_pool_fpm_service],
    notify  => Service[$_pool_fpm_service]
  }
}
