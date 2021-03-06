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
    module Parallel
      def map_each_by_threads(map, options={})
        group_each_by_threads(map.values, options) { |item| yield item }
      end

      def group_each_by_threads(group, options={})
        work_thread = []
        if options[:order] || group.size <= 1
          #serial method
          @logger.debug("#{options[:callee]} run in serial model")
          group.each { |item| yield item }
        else
          #paralleled method for multi-work
          @logger.debug("#{options[:callee]} run in paralleled model")
          group.each do |item|
            work_thread << Thread.new(item) do |item|
              begin
                yield item
              rescue => e
                @logger.debug("#{options[:callee]} threads failed #{e} - #{e.backtrace.join("\n")}")
              end
            end
          end
          @logger.debug("Created #{work_thread.size} threads to work for #{group.size} jobs")
          work_thread.each { |t| t.join }
        end
        @logger.debug("Finish group operation for #{options[:callee]}")
      end

      def vm_deploy_group_pool(thread_pool, group, options={})
        thread_pool.wrap do |pool|
          group.each do |vm|
            @logger.debug("enter : #{vm.pretty_inspect}")
            pool.process do
              begin
                yield(vm)
              rescue
                #TODO do some warning handler here
                raise
              end
            end
            @logger.info("##Finish change one vm_group")
          end
        end
      end

      class ThreadPool
        def initialize(options = {})
          @actions = []
          @lock = Mutex.new
          @cv = ConditionVariable.new
          @max_threads = options[:max_threads] || 1
          @available_threads = @max_threads

          @logger = Serengeti::CloudManager::Cloud.Logger
          @boom = nil
          @original_thread = Thread.current
          @threads = []
          @state = :open
        end

        def wrap
          begin
            yield self
            wait
          ensure
            shutdown
          end
        end

        def pause
          @lock.synchronize do
            @state = :paused
          end
        end

        def resume
          @lock.synchronize do
            @state = :open
            [@available_threads, @actions.size].min.times do
              @available_threads -= 1
              create_thread
            end
          end
        end

        def process(&block)
          @lock.synchronize do
            @actions << block
            if @state == :open
              if @available_threads > 0
                @logger.debug("Creating new thread")
                @available_threads -= 1
                create_thread
              else
                @logger.debug("All threads are currently busy, queuing action")
              end
            elsif @state == :paused
              @logger.debug("Pool is paused, queueing action.")
            end
          end
        end

        def create_thread
          thread = Thread.new do
            begin
              loop do
                action = nil
                @lock.synchronize do
                  action = @actions.shift unless @boom
                  if action
                    @logger.debug("Found an action that needs to be processed")
                  else
                    @logger.debug("Thread is no longer needed, cleaning up")
                    @available_threads += 1
                    @threads.delete(thread) if @state == :open
                  end
                end

                break unless action

                begin
                  action.call
                rescue Exception => e
                  raise_worker_exception(e)
                end
              end
            end
            @lock.synchronize { @cv.signal unless working? }
          end
          @threads << thread
        end

        def raise_worker_exception(exception)
          if exception.respond_to?(:backtrace)
            @logger.debug("Worker thread raised exception: #{exception} - #{exception.backtrace.join("\n")}")
          else
            @logger.debug("Worker thread raised exception: #{exception}")
          end
          @lock.synchronize do
            @boom = exception if @boom.nil?
          end
        end

        def working?
          @boom.nil? && (@available_threads != @max_threads || !@actions.empty?)
        end

        def wait
          @logger.debug("Waiting for tasks to complete")
          @lock.synchronize do
            @cv.wait(@lock) while working?
            raise @boom if @boom
          end
        end

        def shutdown
          return if @state == :closed
          @logger.debug("Shutting down pool")
          @lock.synchronize do
            return if @state == :closed
            @state = :closed
            @actions.clear
          end
          @threads.each { |t| t.join }
        end

      end

    end

    class Cloud
      VM_SPLIT_SIGN = '-'
      def gen_cluster_vm_name(group_name, num)
        return "#{@cluster_name}#{VM_SPLIT_SIGN}#{group_name}#{VM_SPLIT_SIGN}#{num}"
      end

      def vm_is_this_cluster?(vm_name)
        result = get_from_vm_name(vm_name)
        return false unless result
        return false unless (result[1] == @cluster_name)
        true
      end

      def get_from_vm_name(vm_name, options={})
        return /([\w\s\d]+)#{VM_SPLIT_SIGN}([\w\s\d]+)#{VM_SPLIT_SIGN}([\d]+)/.match(vm_name)
      end

    end

  end
end

