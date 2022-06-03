# frozen_string_literal: true

require 'spec_helper'

describe 'puppet_profiles::base' do
  before(:each) do
    # Fake assert_private function from stdlib to not fail within this test
    # https://github.com/rodjek/rspec-puppet/issues/325
    Puppet::Parser::Functions.newfunction(:assert_private, :type => :rvalue) { |args| }
  end
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:pre_condition) do
        'class { "puppet_profiles::base::ubuntu": admin_user_password => "PASSWORD" }'
      end
      let(:facts) do
        os_facts.merge({
          'apt_update_last_success' => -1,
        })
      end

      it { is_expected.to compile }
    end
  end
end
