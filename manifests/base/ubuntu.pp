# @summary Manages the common base configuration of a Ubuntu node
#
#   - It configures the apt update & upgrade policy.
#
# This class must not be included directy. It is automatically included
# by the common puppet_profiles::base profile if appropriate.
#
# @example
#   -- not applicable --
#
# @param unattended_update_time,
#   Value of the 'OnCalendar=' directive of the 'apt-daily' systemd timer.
#   Specifies the time(s) an 'apt update' should be executed by the system.
# @param unattended_update_random_delay,
#   Value of the 'RandomizedDelaySec=' directive of the 'apt-daily' systemd timer.
# @param unattended_upgrade,
#   Wether the system should do unattended security upgrades.
# @param unattended_upgrade_time,
#   Value of the 'OnCalendar=' directive of the 'apt-daily-upgrades' systemd timer.
#   Specifies the time(s) 'unattended-upgrade' should be executed by the system.
# @param unattended_upgrade_random_delay,
#   Value of the 'RandomizedDelaySec=' directive of the 'apt-daily-upgrade' systemd timer.
# @param keyboard_layout
#   The keyboard layout to use.
# @param keyboard_variant
#   The keyboard varaint to use
# @param keyboard_options
#   The keyboard options to use.
# @param locales_available
#   The system locales available.
# @param locales_available
#   The default active system locale.
# @param timedate_timezone
#   The system timezone.
# @param ltimedate_rtc_utc
#   If the Hardware RTC is set to UTC time.
# @param admin_user_name
#   The descriptive name of the admin user. Default value: System Operator.
# @param admin_user_login
#   The login name of the admin user. Default value: sysop
# @param admin_user_password
#   The password of the admin user. Default value: n/a.
# @param admin_user_addon_groups
#   An array of groups the admin user should be a member of in addition to
#   the default group memberships assigned at user creation. By default there is one
#   group specified, its value is looked up from the profile-level hiera variable
#   puppet_profiles::base::ubuntu::admin_group. Default value [operator]
# @param admin_user_public_keys
#   An array of unique values (usually email addresses). The values are looked up as
#   keys from the $admin_user_public_keydefs hash. The defined public keys are added as
#   authorized keys for the account.
# @param admin_user_public_keydefs
#   A Hash containing SSH public-key definitions. By default the content of the hash
#   is aliased to the shared hiera variable 'puppet_profiles::base::ssh_public_keys'.
#   This has the advantage that the key definition may be reused by other classes.
#   
#     profile::server::ssh::keys:
#       alice@example.com:
#         type: ssh-ed25519
#         key: AAAAC3NzaC1lZdeF54E5AAAAIBKQkiccEOf3yww62zTQwZSPX96eL7zVqPmAF56lnW
#         comment: Alice (Login Key)
#       bob@example.com:
#         type: ssh-ed25519
#         key: AAAAC3NzaC1lZdeF54E5AAAAIBKQkiccEOf3yww62zTQwZSPX96eL7zVqPmAF56lnW
#         comment: Bob (Login Key)
#
# @see https://www.freedesktop.org/software/systemd/man/systemd.timer.html#OnCalendar=
# @see https://www.freedesktop.org/software/systemd/man/systemd.timer.html#RandomizedDelaySec=
# 
class puppet_profiles::base::ubuntu (
  String                       $unattended_update_time,
  String                       $unattended_update_random_delay,
  Boolean                      $unattended_upgrade,
  String                       $unattended_upgrade_time,
  String                       $unattended_upgrade_random_delay,
  String                       $keyboard_layout,
  String                       $keyboard_variant,
  String                       $keyboard_options,
  Array[String]                $locales_available,
  String                       $locales_default,
  String                       $timedate_timezone,
  Boolean                      $timedate_rtc_utc,
  String                       $admin_user_name,
  String                       $admin_user_login,
  String                       $admin_user_password,
  Optional[Array[String]]      $admin_user_addon_groups,
  Optional[Array[String]]      $admin_user_public_keys,
  Optional[Hash[String, Hash]] $admin_user_public_keydefs,
){
  assert_private("Use of private class ${name} by ${caller_module_name}")

  include stdlib

  $_distro_version = $facts['os']['distro']['release']['major']

  if $_distro_version != '22.04' {
    fail("The operating system '${puppet_profiles::base::os_report_name}' is not supported by this module!")
  }

  #############################################################################
  ### APT & System-Update Configuration
  #############################################################################

  ::Apt::Ppa <| |>       -> Class['::apt::update']
  ::Apt::Source <| |>    -> Class['::apt::update']
  Class['::apt::update'] -> Package <| provider == 'apt' |>

  ### Wait until a running unattended-upgrade or update is finished

  class { 'puppet_profiles::base::ubuntu_bootstrap':
    stage => 'setup',
  }

  ### Ensure that the APT package index is uptodate

  class { '::apt':
    update => {
      frequency => 'daily',
    },
    keyserver => 'hkp://keyserver.ubuntu.com:80',
  }

  systemd::dropin_file { 'override-apt-update-triggertime':
    unit     => 'apt-daily.timer',
    filename => 'override-triggertime.conf',
    content  => epp('puppet_profiles/base/apt-daily-update-override.epp'),
  }

  ### Configure unattanded security upgrades

  $_unattended_package_state = $unattended_upgrade ? { true => 'present', default => 'purged' }
  $_unattended_file_state    = $unattended_upgrade ? { true => 'present', default => 'absent' }

  class { 'unattended_upgrades':
    package_ensure => $_unattended_package_state,
  }

  # The unattended_upgrades class does not automatically manage the deletion of the
  # configuration files it creates, so we do it here explicitly
  Apt::Conf <| title == 'unattended-upgrades' or title == 'periodic' or title == 'options' |> {
    ensure   => $_unattended_file_state,
  }

  systemd::dropin_file { 'override-apt-upgrade-triggertime':
    ensure   => $_unattended_file_state,
    unit     => 'apt-daily-upgrade.timer',
    filename => 'override-triggertime.conf',
    content  => epp('puppet_profiles/base/apt-daily-upgrade-override.epp'),
  }

  #############################################################################
  ### Ensure important packages are installed                               ###
  #############################################################################

  package { 'cron':
    ensure => installed,
  }

  #############################################################################
  ### Ensure important packages are installed                               ###
  #############################################################################

  package { 'cron':
    ensure => installed,
  }

  #############################################################################
  ### Configure the core locale and language settings
  #############################################################################

  $keyboard_pkgs = ['console-setup', 'keyboard-configuration']
  ensure_packages($keyboard_pkgs)

  file { 'keyboard::configfile':
    ensure  => 'file',
    path    => '/etc/default/keyboard',
    content => epp('puppet_profiles/base/default_keyboard.epp'),
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    require => Package[$keyboard_pkgs]
  }

  exec { 'keyboard::apply::config':
    command     => '/usr/bin/setupcon --save --force --keyboard-only',
    subscribe   => [ File['keyboard::configfile'] ],
    refreshonly => true,
  }

  $locales_pkgs = ['locales']
  ensure_packages($locales_pkgs)

  file { 'locale::configfile::localegen':
    ensure  => present,
    path    => '/etc/locale.gen',
    content => epp('puppet_profiles/base/locale.gen.epp'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package[$locales_pkgs],
  }

  exec { 'locale::apply::localegen':
    command     => '/usr/sbin/locale-gen',
    subscribe   => [ File['locale::configfile::localegen'] ],
    refreshonly => true,
    require     => Package[$locales_pkgs],
  }

  file { 'locale::configfile::default':
    ensure  => present,
    path    => '/etc/default/locale',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('puppet_profiles/base/default_locale.epp'),
    require => Package[$locales_pkgs],
  }

  exec { 'locale::apply::update-locale':
    command     => '/usr/sbin/update-locale',
    subscribe   => [ File['locale::configfile::default'] ],
    refreshonly => true,
    require     => Package[$locales_pkgs],
  }

  #############################################################################
  ### Configure the timezone and set up NTP time synchronization
  #############################################################################

  if $facts['timezone'] != $timedate_timezone {
    exec { 'timedate::apply::timezone':
      command => "/usr/bin/timedatectl set-timezone ${timedate_timezone}",
      before  => Service['systemd-timesyncd'],
    }
  }

  if $facts['rtcutc'] != $timedate_rtc_utc {
    exec { 'timedate::apply::rtc-is-utc':
      command => "/usr/bin/timedatectl set-local-rtc ${!$timedate_rtc_utc}",
      before  => Service['systemd-timesyncd'],
    }
  }

  service { 'systemd-timesyncd':
    ensure   => false,
    provider => 'systemd',
    enable   => false,
  }

  class { '::chrony':
    servers          => {
      'ptbtime1.ptb.de' => ['iburst'],
      'ptbtime2.ptb.de' => ['iburst'],
      'ptbtime3.ptb.de' => ['iburst'],
      'de.pool.ntp.org' => ['iburst'],
    },
    makestep_updates => -1,
    makestep_seconds => 1,
  }

  Service['systemd-timesyncd'] -> Class['::chrony']

  #############################################################################
  ### Create the admin user
  #############################################################################

  group { $admin_user_addon_groups:
    ensure => present,
  }

  $_admin_user_pw = str2sha512shadow($admin_user_password)
  $_admin_user_purge_ssh_keys = $admin_user_public_keys != undef
  $_admin_user_groups = ['adm', 'cdrom', 'sudo', 'dip', 'plugdev'] + $admin_user_addon_groups

  user { $admin_user_login:
    ensure         => present,
    groups         => $_admin_user_groups,
    comment        => $admin_user_name,
    managehome     => true,
    password       => Sensitive($_admin_user_pw),
    purge_ssh_keys => $_admin_user_purge_ssh_keys,
    require        => [Group[$admin_user_addon_groups]],
  }

  if ($admin_user_public_keys != undef) {
    $admin_user_public_keys.each |String $key_id| {
      if ($admin_user_public_keydefs == undef or $admin_user_public_keydefs[$key_id] == undef) {
        fail("Key for ${key_id} not found!")
      } else {
        ssh_authorized_key { "${admin_user_login} (${key_id})":
          ensure => present,
          user   => $admin_user_login,
          type   => $admin_user_public_keydefs[$key_id]['type'],
          key    => $admin_user_public_keydefs[$key_id]['key'],
          name   => $admin_user_public_keydefs[$key_id]['comment'],
        }
      }
    }
  }

  #############################################################################
  ### The rest...
  #############################################################################

  ### By default, purge all unmanaged cron entries of a user

  resources { 'cron': purge => 'true' }
}
