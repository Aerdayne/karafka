# frozen_string_literal: true

# This Karafka component is a Pro component under a commercial license.
# This Karafka component is NOT licensed under LGPL.
#
# All of the commercial components are present in the lib/karafka/pro directory of this
# repository and their usage requires commercial license agreement.
#
# Karafka has also commercial-friendly license, commercial support and commercial components.
#
# By sending a pull request to the pro components, you are agreeing to transfer the copyright of
# your code to Maciej Mensfeld.

module Karafka
  module Pro
    module Processing
      module Strategies
        module Lrj
          # Long-Running Job enabled
          module Default
            include Strategies::Default

            # Pause for tops 31 years
            MAX_PAUSE_TIME = 1_000_000_000_000

            # Features for this strategy
            FEATURES = %i[
              long_running_job
            ].freeze

            # We always need to pause prior to doing any jobs for LRJ
            def handle_before_schedule_consume
              super

              # This ensures that when running LRJ with VP, things operate as expected run only
              # once for all the virtual partitions collectively
              coordinator.on_enqueued do
                # Pause and continue with another batch in case of a regular resume.
                # In case of an error, the `#retry_after_pause` will move the offset to the first
                # message out of this batch.
                pause(:consecutive, MAX_PAUSE_TIME, false)
              end
            end

            # LRJ standard flow after consumption
            def handle_after_consume
              coordinator.on_finished do |last_group_message|
                if coordinator.success?
                  coordinator.pause_tracker.reset

                  return if coordinator.manual_pause?

                  mark_as_consumed(last_group_message) unless revoked?
                  seek(coordinator.seek_offset, false) unless revoked? || coordinator.manual_seek?

                  resume
                else
                  # If processing failed, we need to pause
                  # For long running job this will overwrite the default never-ending pause and
                  # will cause the processing to keep going after the error backoff
                  retry_after_pause
                end
              end
            end

            # We do not un-pause on revokations for LRJ
            def handle_revoked
              coordinator.on_revoked do
                # We do not want to resume on revocation in case of a LRJ.
                # For LRJ we resume after the successful processing or do a backoff pause in case
                # of a failure. Double non-blocking resume could cause problems in coordination.
                coordinator.revoke
              end

              Karafka.monitor.instrument('consumer.revoke', caller: self)
              Karafka.monitor.instrument('consumer.revoked', caller: self) do
                revoked
              end
            end

            # Allows for LRJ to synchronize its work. It may be needed because LRJ can run
            # lifecycle events like revocation while the LRJ work is running and there may be a
            # need for a critical section.
            #
            # @param block [Proc] block we want to run in a mutex to prevent race-conditions
            def synchronize(&block)
              coordinator.shared_mutex.synchronize(&block)
            end
          end
        end
      end
    end
  end
end
