# @summary Manages the base configuration of a node
#
# This profile is included for every node and configures the basic
# operating system settings like timzone, locale and management user.
#
# @example
#   include puppet_profiles::base
# 
class puppet_profiles::base {

  $os_family      = $facts['os']['family']
  $os_name        = $facts['os']['name']
  $os_release     = $facts['os']['release']['full']
  $os_report_name = "${os_family}, ${os_name} (${os_release})"
  $distro_id      = $facts['os']['distro']['id']

  if $os_family == 'Debian' and $distro_id == 'Ubuntu' {
    contain puppet_profiles::base::ubuntu
  } else {
    fail("The operating system '${os_report_name}' is not supported by this module!")
  }
}
