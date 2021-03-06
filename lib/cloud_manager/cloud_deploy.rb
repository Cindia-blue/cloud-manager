###############################################################################
#    Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
################################################################################

# @since serengeti 0.5.0
# @version 0.5.0

module Serengeti
  module CloudManager
    class Cloud
      DEPLOY_GROUP_PARALLEL = "group_parallel"
      DEPLOY_GROUP_ORDER    = "group_order"
      DEPLOY_GROUP_POLICY   = [DEPLOY_GROUP_PARALLEL, DEPLOY_GROUP_ORDER]

      include Serengeti::CloudManager::Parallel

      #TODO cluster_changes
      def cluster_deploy(cluster_changes, vm_placement, options={})
        policy = @input_cluster_info['deploy_policy'] || DEPLOY_GROUP_POLICY.first
        policy.downcase!
        policy = DEPLOY_GROUP_POLICY.first if !DEPLOY_GROUP_POLICY.include?(policy)

        @logger.debug("enter cluster_deploy policy: #{policy}")

        #Begin to parallel deploy vms
        unless cluster_changes.empty?
          cluster_changes.each do |group|
            group_each_by_threads(group, :callee=>'deploy changes', :order=>(policy==DEPLOY_GROUP_ORDER)) do |vm|
              #TODO add change code here
              @logger.info("changing vm #{vm.pretty_inspect}")
              vm.status = VM_STATE_DONE
            end
          end
          @logger.info("Finish all changes")
        end

        group_each_by_threads(vm_placement, :order=>(policy==DEPLOY_GROUP_ORDER), :callee=>'deploy group') do |group|
          deploy_vm_group(group)
        end

        @logger.info("Finish all deployments")
        "finished"
      end

      def vm_deploy_op(vm, working, vms = @existed_vms)
        begin
          yield
          return 'OK'
        rescue => e
          @logger.error("#{working} vm:#{vm.name} failed.\n #{e} - #{e.backtrace.join("\n")}")
          vm.error_code = -1
          vm.error_msg = "#{working} vm:#{vm.name} failed. #{e}"
          mov_vm(vm, vms, @failed_vms)
          return nil
        end
      end

      def deploy_vm_group(group)
        group_each_by_threads(group, :callee=>'deploy vms') do |vm|
          begin
            if (vm.error_code.to_i != 0)
              @logger.debug("vm #{vm.name} can not deploy because:#{vm.error_msg}.")
              next
            end
            vm.status = VM_STATE_CLONE
            mov_vm(vm, @placed_vms, @deploy_vms)
            next if !vm_deploy_op(vm, 'Clone', @deploy_vms) { @client.clone_vm(vm, :poweron => false)}
            @logger.info("vm:#{vm.name} power:#{vm.power_state} finish clone")

            #is this VM can do HA?
            vm.can_ha = @client.is_vm_in_ha_cluster(vm)

            vm.status = VM_STATE_RECONFIG
            next if !vm_deploy_op(vm, 'Reconfigure disk', @deploy_vms) { vm_reconfigure_disk(vm)}
            @logger.info("vm:#{vm.name} finish reconfigure disk")

            next if !vm_deploy_op(vm, 'Reconfigure network', @deploy_vms) {vm_reconfigure_network(vm)}
            @logger.info("vm:#{vm.name} finish reconfigure networking")

            #Move deployed vm to existed queue
            mov_vm(vm, @deploy_vms, @existed_vms)
          ensure
            if vm.error_code.to_i != 0
              @client.vm_destroy(vm)
              vm.status = VM_STATE_DELETED
              vm.deleted = true
            end
          end

        end
      end

      def vm_reconfigure_disk(vm, options={})
        vm.disks.each_value { |disk| @client.vm_create_disk(vm, disk) if disk.unit_number > 0}
      end

      def vm_reconfigure_network(vm, options = {})
        @client.vm_update_network(vm) unless vm.network_config_json.nil?
      end

      def vm_finish(vm, options={})
        mov_vm(vm, @existed_vms, @finished_vms)
      end

      ###################################
      # inner used functions
      def gen_disk_name(datastore, vm, type, unit_number)
        return "[#{datastore.name}] #{vm.name}/#{type}-disk-#{unit_number}.vmdk"
      end

    end
  end
end
