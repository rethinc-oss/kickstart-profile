class puppet_profiles::mysql {
  $override_options = {
    'mysqld' => {
      'bind-address' => '0.0.0.0',
    }
  }

  class { '::mysql::server':
    package_name            => 'mysql-server',
    service_name            => 'mysql',
    root_password           => 'root',
    remove_default_accounts => true,
    restart                 => true,
    override_options        => $override_options,
  }

  class { '::mysql::client':
    package_name            => 'mysql-client',
  }
}
