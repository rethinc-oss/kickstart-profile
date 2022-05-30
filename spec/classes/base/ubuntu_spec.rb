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
      
      $update_dropin_file  = '/etc/systemd/system/apt-daily.timer.d/override-triggertime.conf'
      $upgrade_dropin_file = '/etc/systemd/system/apt-daily-upgrade.timer.d/override-triggertime.conf'
      $custom_time         = 'CUSTOMTIME'
      $custom_delay        = 'CUSTOMDELAY'

      it do
        is_expected.to compile.with_all_deps
        is_expected.to contain_file($update_dropin_file)
        is_expected.to contain_file($upgrade_dropin_file).with_ensure('absent')
        is_expected.to contain_package('unattended-upgrades').with_ensure('purged')
      end

      context 'with custom update parameters' do
        let(:params) { {'unattended_update_time' => $custom_time, 'unattended_update_random_delay' => $custom_delay} }
        
        it do
          is_expected.to contain_file($update_dropin_file) \
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
            is_expected.to contain_file($upgrade_dropin_file) \
              .with_content(/^OnCalendar=#{$custom_time}$/)
              .with_content(/^RandomizedDelaySec=#{$custom_delay}$/)
          end
        end  
      end
    end
  end
end
