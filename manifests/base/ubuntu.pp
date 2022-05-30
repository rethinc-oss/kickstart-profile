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
#
# @see https://www.freedesktop.org/software/systemd/man/systemd.timer.html#OnCalendar=
# @see https://www.freedesktop.org/software/systemd/man/systemd.timer.html#RandomizedDelaySec=
# 
class puppet_profiles::base::ubuntu (
    String  $unattended_update_time,
    String  $unattended_update_random_delay,
    Boolean $unattended_upgrade,
    String  $unattended_upgrade_time,
    String  $unattended_upgrade_random_delay,
){
  assert_private("Use of private class ${name} by ${caller_module_name}")

  include stdlib

  $_distro_version = $facts['os']['distro']['release']['major']

  if $_distro_version != '22.04' {
    fail("The operating system '${puppet_profiles::base::os_report_name}' is not supported by this module!")
  }

#  if $caller_module_name != $module_name {
#    fail("Use of private class ${name} by ${caller_module_name}")
#  }

  #############################################################################
  ### APT & System-Update Configuration
  #############################################################################

  ::Apt::Ppa <| |> -> Class['::apt::update'] -> Package <| provider == 'apt' |>

  ### Wait until a running unattended-upgrade or update is finished

  class { 'puppet_profiles::base::ubuntu_bootstrap':
    stage => 'setup',
  }

  ### Ensure that the APT package index is uptodate

  class { '::apt':
    update => {
      frequency => 'daily',
    },
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
}
