module RSpec
  module Mocks
    module Matchers
      # @private
      class ReceiveMessageChain
        def initialize(chain, &block)
          @chain = chain
          @block = block
          @recorded_customizations  = []
        end

        [:and_return, :and_throw, :and_raise, :and_yield, :and_call_original].each do |msg|
          define_method(msg) do |*args, &block|
            @recorded_customizations << ExpectationCustomization.new(msg, args, block)
            self
          end
        end

        def name
          "receive_message_chain"
        end

        def setup_allowance(subject, &block)
          chain = StubChain.stub_chain_on(subject, *@chain, &(@block || block))
          replay_customizations(chain)
        end

        def setup_any_instance_allowance(subject, &block)
          recorder = ::RSpec::Mocks.any_instance_recorder_for(subject)
          chain = recorder.stub_chain(*@chain, &(@block || block))
          replay_customizations(chain)
        end

        def setup_any_instance_expectation(subject, &block)
          recorder = ::RSpec::Mocks.any_instance_recorder_for(subject)
          chain = recorder.expect_chain(*@chain, &(@block || block))
          replay_customizations(chain)
        end

        def setup_expectation(subject, &block)
          chain = ExpectChain.expect_chain_on(subject, *@chain, &(@block || block))
          replay_customizations(chain)
        end

        def setup_negative_expectation(*args)
          raise NegationUnsupportedError.new(
            "`expect(...).not_to receive_message_chain` is not supported " +
            "since it doesn't really make sense. What would it even mean?"
          )
        end

        alias matches? setup_expectation
        alias does_not_match? setup_negative_expectation

        private

        def replay_customizations(chain)
          @recorded_customizations.each do |customization|
            customization.playback_onto(chain)
          end
        end
      end
    end
  end
end
