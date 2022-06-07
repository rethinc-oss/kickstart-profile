define puppet_profiles::nginx::intern::vhost_user (
  String                       $homedir,
  Boolean                      $manage_homedir,
  Optional[String]             $addon_group,
  Optional[Array[String]]      $public_keys,
  Optional[Hash[String, Hash]] $public_keydefs,
){
  # TODO: Add comment
  if $manage_homedir {
    $_create_user_params = {
      ensure     => 'present',
      home       => $homedir,
      groups     => $addon_group,
      managehome => true,
      before     => User[$nginx::params::daemon_user],
    }
  } else {
    $_create_user_params = {
      ensure     => 'present',
      groups     => $addon_group,
      before     => User[$nginx::params::daemon_user],
    }
  }

  if ($addon_group != undef) {
    group { $addon_group:
      ensure => present,
    }
  }

  #Can happen when provisioning a local development vagrant machine
  #TODO: Investigate if there is a better solution
  if !defined(User[$title]) {
    user { $title:
      *       => $_create_user_params,
      require => [Group[$addon_group]],
    }
  }

  # Make the webserver name member of the primary group of the vhost name
  User <| title == $nginx::params::daemon_user |> { groups +> $title }

  if ($public_keys != undef) {
    $public_keys.each |String $key_id| {
      if ($public_keydefs == undef or $public_keydefs[$key_id] == undef) {
        fail("Key for ${key_id} not found!")
      } else {
        ssh_authorized_key { "${title} (${key_id})":
          ensure => present,
          user   => $name,
          type   => $public_keydefs[$key_id]['type'],
          key    => $public_keydefs[$key_id]['key'],
          name   => $public_keydefs[$key_id]['comment'],
        }
      }
    }
  }
}
