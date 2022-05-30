# frozen_string_literal: true

require 'spec_helper'

describe 'puppet_profiles::base' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) do
        os_facts.merge({
          'apt_update_last_success' => -1,
        })
      end

      it { is_expected.to compile }
    end
  end
end
