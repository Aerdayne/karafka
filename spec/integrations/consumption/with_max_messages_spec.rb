# frozen_string_literal: true

# Karafka should not return more messages than defined with `max_messages`

setup_karafka

produce_many(DT.topic, DT.uuids(40))

class Consumer < Karafka::BaseConsumer
  def consume
    DT[:counts] << messages.size
  end
end

draw_routes do
  topic DT.topic do
    max_messages 5
    max_wait_time 10_000
    consumer Consumer
  end
end

start_karafka_and_wait_until do
  DT[:counts].size >= 8
end

assert_equal 5, DT[:counts].max
# We should get at least 8 batches 5 messages each but if there is a hiccup, we may get more with
# less in each
assert DT[:counts].size >= 8
