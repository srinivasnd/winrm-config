require 'spec_helper'

describe 'winrm_config_listener' do
  describe 'action create' do
    let(:chef_run) do
      ChefSpec::SoloRunner.new(step_into: ['winrm_config_listener']).converge('winrm-config-test::configure_listener')
    end

    before do
      stub_command('netsh http show urlacl url=http://+:5985/wsman/').and_return true
    end

    it 'creates listener registry key' do
      expect(chef_run).to configure_winrm_config_listener('configure_listener')
      expect(chef_run).to create_registry_key('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener\*+HTTP')
    end
  end

  describe 'action delete' do
    let(:chef_run) do
      ChefSpec::SoloRunner.new(step_into: ['winrm_config_listener']).converge('winrm-config-test::delete_listener')
    end

    it 'deletes listener registry key' do
      expect(chef_run).to delete_winrm_config_listener('delete_listener')
      expect(chef_run).to delete_registry_key('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener\*+HTTPS')
    end
  end
end
