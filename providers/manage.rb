#
# Cookbook Name:: users
# Provider:: manage
#
# Copyright 2011, Eric G. Wolfe
# Copyright 2009-2011, Opscode, Inc.
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

def whyrun_supported?
  true
end

def initialize(*args)
  super
  @action = :create
end

action :remove do
  if Chef::Config[:solo]
    Chef::Log.warn("This recipe uses search. Chef Solo does not support search.")
  else
    search(new_resource.data_bag, "groups:#{new_resource.search_group} AND action:remove") do |rm_user|
      user rm_user['username'] ||= rm_user['id'] do
        action :remove
      end
    end
    new_resource.updated_by_last_action(true)
  end
end

action :create do
  security_group = Array.new

  if Chef::Config[:solo]
    Chef::Log.warn("This recipe uses search. Chef Solo does not support search.")
  else
    search(new_resource.data_bag, "groups:#{new_resource.search_group} AND NOT action:remove") do |u|
      u['username'] ||= u['id']
      security_group << u['username']

      if node['apache'] and node['apache']['allowed_openids']
        Array(u['openid']).compact.each do |oid|
          node['apache']['allowed_openids'] << oid unless node['apache']['allowed_openids'].include?(oid)
        end
      end

      # Set home to location in data bag,
      # or a reasonable default (/home/$user).
      default_home = case node['platform']
                       when 'mac_os_x' then '/Users/'
                       else '/home/'
                     end
      if u['home']
        home_dir = u['home']
      else
        home_dir = default_home + u['username']
      end

      # The user block will fail if the group does not yet exist.
      # See the -g option limitations in man 8 useradd for an explanation.
      # This should correct that without breaking functionality.
      if u['gid'] and u['gid'].kind_of?(Numeric)
        group u['username'] do
          gid u['gid']
        end
      end

      # Create user object.
      # Do NOT try to manage null home directories.
      user u['username'] do
        uid u['uid']
        if u['gid']
          gid u['gid']
        end
        shell u['shell']
        comment u['comment']
        password u['password'] if u['password']
        if home_dir == "/dev/null"
          supports :manage_home => false
        else
          supports :manage_home => true
        end
        home home_dir
      end

      default_group = case node['platform']
                        when 'mac_os_x' then 'admin'
                        else u['username']
                      end

      if home_dir != "/dev/null"
        directory home_dir do
          owner u['username']
          group u['gid'] || default_group
          mode "0700"
        end
        directory "#{home_dir}/.ssh" do
          owner u['username']
          group u['gid'] || default_group
          mode "0700"
        end

        if u['ssh_keys']
          template "#{home_dir}/.ssh/authorized_keys" do
            source "authorized_keys.erb"
            cookbook new_resource.cookbook
            owner u['username']
            group u['gid'] || default_group
            mode "0600"
            variables :ssh_keys => u['ssh_keys']
          end
        end
      end
    end
  end

  group new_resource.group_name do
    gid new_resource.group_id
    members security_group
  end
  new_resource.updated_by_last_action(true)
end
