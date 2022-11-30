class puppet_profiles::mailhog {
  include ::stdlib

  ensure_packages(['golang'])

  exec { 'install_mailhog':
    command     => '/usr/bin/go install github.com/mailhog/MailHog@v1.0.1',
    environment => ['GOPATH=/opt/go', 'GOCACHE=/opt/go/cache'],
    creates     => '/opt/go/bin/MailHog/',
    require     => [ Package['golang'] ],
  }

  systemd::unit_file { 'mailhog.service':
    content => epp('puppet_profiles/mailhog/mailhog.service.epp'),
    enable  => true,
    active  => true,
    require => [Exec['install_mailhog']],
  }
}
