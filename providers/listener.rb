#
# Author:: Baptiste Courtois (<b.courtois@criteo.com>)
# Cookbook Name:: winrm-config
# Provider:: listener
#
# Copyright:: Copyright (c) 2014 Criteo.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include Chef::DSL::RegistryHelper

use_inline_resources

def whyrun_supported?
  true
end

def load_current_resource
  return unless registry_key_exists? new_resource.key_name

  @current_resource = Chef::Resource::WinrmConfigListener.new(new_resource.name, run_context)
  @current_resource.address new_resource.address
  @current_resource.transport new_resource.transport

  data = registry_hash_values new_resource.key_name
  @current_resource.port(data['Port'])
  @current_resource.enabled(data['enabled'] == 1)
  @current_resource.hostname(data['hostname'])
  @current_resource.url_prefix(data['uriprefix'])
  @current_resource.certificate_thumbprint(data['certThumbprint'])
end

def exist?
  !@current_resource.nil?
end

def shared_url?
  registry_get_subkeys(Chef::Resource::WinrmConfigListener.LISTENER_KEY).select do |key|
    next unless key.end_with? new_resource.transport.to_s

    values = registry_hash_values "#{Chef::Resource::WinrmConfigListener.LISTENER_KEY}\\#{key}"
    new_resource.port == values['Port'] && new_resource.url_prefix == values['uriprefix']
  end.count > 1
end

def registry_hash_values(key)
  Hash[registry_get_values(key).map { |elt| [elt[:name], elt[:data]] }]
end

def url_acl_changed?
  [:address, :port].any? do |attribute|
    @new_resource.send(attribute) != @current_resource.send(attribute)
  end
end

def ssl_binding_changed?
  [:certificate_thumbprint, :address, :port].any? do |attribute|
    @new_resource.send(attribute) != @current_resource.send(attribute)
  end
end

action :configure do
  if exist?
    execute "Remove former URI binding #{current_resource.uri}" do
      command "netsh http delete urlacl url=#{current_resource.uri}"
      only_if { url_acl_changed? }
      only_if "netsh http show urlacl url=#{current_resource.uri}"
    end

    execute "Remove former ssl certificate for #{current_resource.ip}:#{current_resource.port}" do
      command "netsh http delete sslcert ipport=#{current_resource.ip}:#{current_resource.port}"
      only_if { new_resource.transport == :HTTPS && ssl_binding_changed? }
      only_if "netsh http show sslcert ipport=#{current_resource.ip}:#{current_resource.port}"
    end
  end

  execute "Bind listener to winrm URI (url=#{new_resource.uri} SDDL=#{WINRM_SDDL})" do
    command "netsh http add urlacl url=#{new_resource.uri} SDDL=#{WINRM_SDDL}"
    only_if { !exist? || url_acl_changed? }
    not_if "netsh http show urlacl url=#{new_resource.uri}"
  end

  execute "Bind ssl certificate to winrm listener #{new_resource.ip}:#{new_resource.port}" do
    command "netsh http add sslcert ipport=#{new_resource.ip}:#{new_resource.port} certhash=#{new_resource.certificate_thumbprint} appid=#{WINRM_APPID}"
    only_if { new_resource.transport == :HTTPS &&  (!exist? || ssl_binding_changed?) }
    not_if "netsh http show sslcert ipport=#{new_resource.ip}:#{new_resource.port}"
  end

  registry_key new_resource.key_name do
    action    :create
    recursive true
    values [
      { name: 'enabled',        type: :dword,  data: new_resource.enabled ? 1 : 0 },
      { name: 'hostname',       type: :string, data: new_resource.hostname },
      { name: 'certThumbprint', type: :string, data: new_resource.certificate_thumbprint },
      { name: 'Port',           type: :dword,  data: new_resource.port },
      { name: 'uriprefix',      type: :string, data: new_resource.url_prefix },
    ]
  end
end

action :delete do
  if exist?
    execute "Remove URI binding #{new_resource.uri}" do
      command "netsh http delete urlacl url=#{new_resource.uri}"
      not_if { shared_url? }
      only_if "netsh http show urlacl url=#{new_resource.uri}"
    end

    execute "Remove ssl certificate for #{new_resource.ip}:#{new_resource.port}" do
      command "netsh http delete sslcert ipport=#{new_resource.ip}:#{new_resource.port}"
      only_if { new_resource.transport == :HTTPS }
      only_if "netsh http show sslcert ipport=#{new_resource.ip}:#{new_resource.port}"
    end
  end

  registry_key new_resource.key_name do
    action    :delete
  end
end

private

WINRM_APPID = '{afebb9ad-9b97-4a91-9ab5-daf4d59122f6}'
WINRM_SDDL = 'D:(A;;GX;;;S-1-5-80-569256582-2953403351-2909559716-1301513147-412116970)(A;;GX;;;S-1-5-80-4059739203-877974739-1245631912-527174227-2996563517)'
