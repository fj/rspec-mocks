require 'spec_helper'
require 'delegate'

describe "and_call_original" do
  context "on a partial double" do
    let(:klass) do
      Class.new do
        def meth_1
          :original
        end

        def meth_2(x)
          yield x, :additional_yielded_arg
        end

        def self.new_instance
          new
        end
      end
    end

    let(:instance) { klass.new }

    context "when a method that exists has been stubbed previously" do
      before { allow(instance).to receive(:meth_1).and_return(:override) }

      it 'restores the original behavior' do
        expect {
          allow(instance).to receive(:meth_1).and_call_original
        }.to change(instance, :meth_1).from(:override).to(:original)
      end
    end

    context "when a non-existant method has been stubbed previously" do
      it 'restores the original NameError behavior' do
        message = nil
        expect { instance.abcd }.to raise_error(NameError) { |msg| message = msg.message }

        allow(instance).to receive(:abcd).and_return(:override)
        expect(instance.abcd).to eq(:override)

        allow(instance).to receive(:abcd).and_call_original
        expect { instance.abcd }.to raise_error(NameError).with_message(message)
      end
    end

    it 'passes the received message through to the original method' do
      expect(instance).to receive(:meth_1).and_call_original
      expect(instance.meth_1).to eq(:original)
    end

    it 'ignores prior declared stubs' do
      instance.stub(:meth_1).and_return(:stubbed_value)
      instance.should_receive(:meth_1).and_call_original
      expect(instance.meth_1).to eq(:original)
    end

    it 'passes args and blocks through to the original method' do
      expect(instance).to receive(:meth_2).and_call_original
      value = instance.meth_2(:submitted_arg) { |a, b| [a, b] }
      expect(value).to eq([:submitted_arg, :additional_yielded_arg])
    end

    it 'errors when you pass through the wrong number of args' do
      expect(instance).to receive(:meth_1).and_call_original
      expect(instance).to receive(:meth_2).twice.and_call_original
      expect { instance.meth_1 :a }.to raise_error ArgumentError
      expect { instance.meth_2 {} }.to raise_error ArgumentError
      expect { instance.meth_2(:a, :b) {}  }.to raise_error ArgumentError
    end

    it 'warns when you override an existing implementation' do
      expect(RSpec).to receive(:warning).with(/overriding a previous stub implementation of `meth_1`.*#{__FILE__}:#{__LINE__ + 1}/)
      expect(instance).to receive(:meth_1) { true }.and_call_original
      instance.meth_1
    end

    context "for singleton methods" do
      it 'works' do
        def instance.foo; :bar; end
        instance.should_receive(:foo).and_call_original
        expect(instance.foo).to eq(:bar)
      end

      it 'works for SimpleDelegator subclasses', :if => (RUBY_VERSION.to_f > 1.8) do
        instance = Class.new(SimpleDelegator).new(1)
        def instance.foo; :bar; end
        instance.should_receive(:foo).and_call_original
        expect(instance.foo).to eq(:bar)
      end
    end

    it 'works for methods added through an extended module' do
      instance.extend Module.new { def foo; :bar; end }
      instance.should_receive(:foo).and_call_original
      expect(instance.foo).to eq(:bar)
    end

    it "works for method added through an extended module onto a class's ancestor" do
      sub_sub_klass = Class.new(Class.new(klass))
      klass.extend Module.new { def foo; :bar; end }
      sub_sub_klass.should_receive(:foo).and_call_original
      expect(sub_sub_klass.foo).to eq(:bar)
    end

    it "finds the method on the most direct ancestor even if the method " +
       "is available on more distant ancestors" do
      klass.extend Module.new { def foo; :klass_bar; end }
      sub_klass = Class.new(klass)
      sub_klass.extend Module.new { def foo; :sub_klass_bar; end }
      sub_klass.should_receive(:foo).and_call_original
      expect(sub_klass.foo).to eq(:sub_klass_bar)
    end

    it "finds the method on the most direct singleton class ancestors even if the method " +
       "is available on more distant ancestors" do
      klass.extend Module.new { def foo; :klass_bar; end }
      sub_klass = Class.new(klass) { def self.foo; :sub_klass_bar; end }
      sub_sub_klass = Class.new(sub_klass)
      sub_sub_klass.should_receive(:foo).and_call_original
      expect(sub_sub_klass.foo).to eq(:sub_klass_bar)
    end

    context 'when using any_instance' do
      it 'works for instance methods defined on the class' do
        klass.any_instance.should_receive(:meth_1).and_call_original
        expect(klass.new.meth_1).to eq(:original)
      end

      it 'works for instance methods defined on the superclass of the class' do
        subclass = Class.new(klass)
        subclass.any_instance.should_receive(:meth_1).and_call_original
        expect(subclass.new.meth_1).to eq(:original)
      end

      it 'works when mocking the method on one class and calling the method on an instance of a subclass' do
        klass.any_instance.should_receive(:meth_1).and_call_original
        expect(Class.new(klass).new.meth_1).to eq(:original)
      end
    end

    it 'works for class methods defined on a superclass' do
      subclass = Class.new(klass)
      subclass.should_receive(:new_instance).and_call_original
      expect(subclass.new_instance).to be_a(subclass)
    end

    it 'works for class methods defined on a grandparent class' do
      sub_subclass = Class.new(Class.new(klass))
      sub_subclass.should_receive(:new_instance).and_call_original
      expect(sub_subclass.new_instance).to be_a(sub_subclass)
    end

    it 'works for class methods defined on the Class class' do
      klass.should_receive(:new).and_call_original
      expect(klass.new).to be_an_instance_of(klass)
    end

    it "works for instance methods defined on the object's class's superclass" do
      subclass = Class.new(klass)
      inst = subclass.new
      inst.should_receive(:meth_1).and_call_original
      expect(inst.meth_1).to eq(:original)
    end

    it 'works for aliased methods' do
      klass = Class.new do
        class << self
          alias alternate_new new
        end
      end

      klass.should_receive(:alternate_new).and_call_original
      expect(klass.alternate_new).to be_an_instance_of(klass)
    end

    context 'on an object that defines method_missing' do
      before do
        klass.class_exec do
          private

          def method_missing(name, *args)
            if name.to_s == "greet_jack"
              "Hello, jack"
            else
              super
            end
          end
        end
      end

      it 'works when the method_missing definition handles the message' do
        instance.should_receive(:greet_jack).and_call_original
        expect(instance.greet_jack).to eq("Hello, jack")
      end

      it 'works for an any_instance partial mock' do
        klass.any_instance.should_receive(:greet_jack).and_call_original
        expect(instance.greet_jack).to eq("Hello, jack")
      end

      it 'raises an error for an unhandled message for an any_instance partial mock' do
        klass.any_instance.should_receive(:not_a_handled_message).and_call_original
        expect {
          instance.not_a_handled_message
        }.to raise_error(NameError, /not_a_handled_message/)
      end

      it 'raises an error on invocation if method_missing does not handle the message' do
        instance.should_receive(:not_a_handled_message).and_call_original

        # Note: it should raise a NoMethodError (and usually does), but
        # due to a weird rspec-expectations issue (see #183) it sometimes
        # raises a `NameError` when a `be_xxx` predicate matcher has been
        # recently used. `NameError` is the superclass of `NoMethodError`
        # so this example will pass regardless.
        # If/when we solve the rspec-expectations issue, this can (and should)
        # be changed to `NoMethodError`.
        expect {
          instance.not_a_handled_message
        }.to raise_error(NameError, /not_a_handled_message/)
      end
    end
  end

  context "on a partial double that overrides #method" do
    let(:request_klass) do
      Struct.new(:method, :url) do
        def perform
          :the_response
        end

        def self.method
          :some_method
        end
      end
    end

    let(:request) { request_klass.new(:get, "http://foo.com/bar") }

    it 'still works even though #method has been overriden' do
      request.should_receive(:perform).and_call_original
      expect(request.perform).to eq(:the_response)
    end

    it 'works for a singleton method' do
      def request.perform
        :a_response
      end

      request.should_receive(:perform).and_call_original
      expect(request.perform).to eq(:a_response)
    end
  end

  context "on a pure test double" do
    let(:instance) { double }

    it 'raises an error even if the double object responds to the message' do
      expect(instance.to_s).to be_a(String)
      mock_expectation = instance.should_receive(:to_s)
      instance.to_s # to satisfy the expectation

      expect {
        mock_expectation.and_call_original
      }.to raise_error(/pure test double.*and_call_original.*partial double/i)
    end
  end
end

