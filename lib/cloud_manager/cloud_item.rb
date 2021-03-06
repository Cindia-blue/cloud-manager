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
    STATE_RUNNING = "running"
    STATE_FAILED = "failed"
    STATE_SUCCESS = "success"

    DISK_TYPE_SHARE = 'shared'
    DISK_TYPE_LOCAL = 'local'
    class ResourceInfo
      DISK_SIZE_UNIT_CONVERTER = 1024
      attr_accessor :cpu
      attr_accessor :mem
      attr_accessor :disk_type
      attr_accessor :disk_size
      attr_accessor :disk_pattern
      attr_accessor :rack_id
      attr_accessor :template_id
      attr_accessor :affinity
      attr_accessor :ha
      def initialize(rp=nil)
        if rp
          @cpu = rp["cpu"] || 1
          @mem = rp["memory"] || 512
          @disk_size =  rp["storage"]["size"] || 0
          @disk_pattern = rp["storage"]["name_pattern"]
          @disk_size *= DISK_SIZE_UNIT_CONVERTER
          @disk_type = rp["storage"]["type"]
          @disk_type = DISK_TYPE_SHARE if @disk_type != DISK_TYPE_LOCAL
          @affinity = rp["affinity"] || "none"
          @template_id = rp["template_id"]
          @ha = rp["ha"]
          @ha = true if @ha.nil?
          @rack_id = nil
        end
      end
    end

    class DiskInfo
      attr_accessor :type
      attr_accessor :fullpath
      attr_accessor :size
      attr_accessor :unit_number
      attr_accessor :datastore_name
      attr_accessor :shared
    end

  end
end
