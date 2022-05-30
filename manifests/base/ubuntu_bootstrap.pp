class puppet_profiles::base::ubuntu_bootstrap {
  exec { 'wait-unattended-apt':
    command => '/usr/bin/systemd-run --property="After=apt-daily.service apt-daily-upgrade.service" --no-ask-password --wait /bin/true',
  }
}
