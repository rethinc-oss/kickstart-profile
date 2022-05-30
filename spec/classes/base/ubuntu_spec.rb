# frozen_string_literal: true

require 'spec_helper'

describe 'puppet_profiles::base::ubuntu' do
  before(:each) do
    # Fake assert_private function from stdlib to not fail within this test
    # https://github.com/rodjek/rspec-puppet/issues/325
    Puppet::Parser::Functions.newfunction(:assert_private, :type => :rvalue) { |args| }
  end
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) do
        os_facts.merge({
          'apt_update_last_success' => -1,
        })
      end

      $update_dropin_file    = '/etc/systemd/system/apt-daily.timer.d/override-triggertime.conf'
      $upgrade_dropin_file   = '/etc/systemd/system/apt-daily-upgrade.timer.d/override-triggertime.conf'
      $custom_time           = 'CUSTOMTIME'
      $custom_delay          = 'CUSTOMDELAY'
      $custom_kb_layout      = 'CUSTOMLAYOUT'
      $custom_kb_variant     = 'CUSTOMVARIANT'
      $custom_kb_options     = 'CUSTOMOPTIONS'
      $custom_locale_default = 'CUSTOMLOCALE'

      it do
        is_expected.to compile.with_all_deps
        is_expected.to contain_file($update_dropin_file)
        is_expected.to contain_file($upgrade_dropin_file).with_ensure('absent')
        is_expected.to contain_package('unattended-upgrades').with_ensure('purged')

        is_expected.to contain_file('keyboard::configfile').with_path('/etc/default/keyboard')
        is_expected.to contain_file('locale::configfile::localegen').with_path('/etc/locale.gen')
        is_expected.to contain_file('locale::configfile::default').with_path('/etc/default/locale')
      end

      context 'with custom update parameters' do
        let(:params) { {'unattended_update_time' => $custom_time, 'unattended_update_random_delay' => $custom_delay} }

        it do
          is_expected.to contain_file($update_dropin_file)
            .with_content(/^OnCalendar=#{$custom_time}$/)
            .with_content(/^RandomizedDelaySec=#{$custom_delay}$/)
        end
      end

      context 'with unattended_upgrade enabled' do
        let(:params) { {'unattended_upgrade' => true} }

        it do
          is_expected.to contain_file($upgrade_dropin_file)
          is_expected.to contain_package('unattended-upgrades').with_ensure('present')
        end

        context 'with custom upgrade parameters' do
          let(:params) { {'unattended_upgrade_time' => $custom_time, 'unattended_upgrade_random_delay' => $custom_delay} }

          it do
            is_expected.to contain_file($upgrade_dropin_file)
              .with_content(/^OnCalendar=#{$custom_time}$/)
              .with_content(/^RandomizedDelaySec=#{$custom_delay}$/)
          end
        end

        context 'with custom keyboard layout' do
          let(:params) {{
            'keyboard_layout' => $custom_kb_layout,
            'keyboard_variant' => $custom_kb_variant,
            'keyboard_options' => $custom_kb_options
          }}
      
          it do
            is_expected.to contain_file('keyboard::configfile')
              .with_content(/^XKBLAYOUT=\"#{$custom_kb_layout}\"$/)
              .with_content(/^XKBVARIANT=\"#{$custom_kb_variant}\"$/)
              .with_content(/^XKBOPTIONS=\"#{$custom_kb_options}\"$/)
          end
        end

        context 'with custom default locale' do
          let(:params) {{
            'locales_default' => $custom_locale_default,
          }}
      
          it do
            is_expected.to contain_file('locale::configfile::default')
              .with_content(/^LANG=\"#{$custom_locale_default}\"$/)
          end
        end
      end
    end
  end
end
