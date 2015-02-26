#
# Copyright 2015, Noah Kantrowitz
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chefspec'
require 'halite/spec_helper/runner'

module Halite
  # A helper module for RSpec tests of resource-based cookbooks.
  #
  # @since 1.0
  # @example
  #   describe MyMixin do
  #     resource(:my_thing) do
  #       include Poise
  #       include MyMixin
  #       action(:install)
  #       attribute(:path, kind_of: String, default: '/etc/thing')
  #     end
  #     provider(:my_thing) do
  #       include Poise
  #       def action_install
  #         file new_resource.path do
  #           content new_resource.my_mixin
  #         end
  #       end
  #     end
  #     recipe do
  #       my_thing 'test'
  #     end
  #
  #     it { is_expected.to create_file('/etc/thing').with(content: 'mixin stuff') }
  #   end
  module SpecHelper
    extend RSpec::SharedContext
    let(:step_into) { [] }
    let(:default_attributes) { Hash.new }
    let(:normal_attributes) { Hash.new }
    let(:override_attributes) { Hash.new }
    let(:chefspec_options) { Hash.new }
    let(:chef_runner) do
      Halite::SpecHelper::Runner.new(
        {
          step_into: step_into,
          default_attributes: default_attributes,
          normal_attributes: normal_attributes,
          override_attributes: override_attributes,
        }.merge(chefspec_options)
      )
    end

    # An alias for slightly more semantic meaning, just forces the lazy #subject
    # to run.
    #
    # @see http://www.relishapp.com/rspec/rspec-core/v/3-2/docs/subject/explicit-subject RSpec's subject helper
    # @example
    #   describe 'my recipe' do
    #     recipe 'my_recipe'
    #     it { run_chef }
    #   end
    def run_chef
      subject
    end

    private

    # Patch an object in to a global namespace for the duration of a block.
    #
    # @param mod [Module] Namespace to patch in to.
    # @param name [String, Symbol] Name to create in snake-case (eg. :my_name).
    # @param obj Object to patch in.
    # @param block [Proc] Block to execute while the name is available.
    def patch_module(mod, name, obj, &block)
      class_name = Chef::Mixin::ConvertToClassName.convert_to_class_name(name.to_s)
      if mod.const_defined?(class_name, false)
        old_class = mod.const_get(class_name, false)
        # We are only allowed to patch over things installed by patch_module
        raise "#{mod.name}::#{class_name} is already defined" if !old_class.instance_variable_get(:@poise_patch_module)
        # Remove it before setting to avoid the redefinition warning
        mod.send(:remove_const, class_name)
      end
      # Tag our objects so we know we are allowed to overwrite those, but not other stuff.
      obj.instance_variable_set(:@poise_patch_module, true)
      mod.const_set(class_name, obj)
      begin
        block.call
      ensure
        # Same as above, have to remove before set because warnings
        mod.send(:remove_const, class_name)
        mod.const_set(class_name, old_class) if old_class
      end
    end

    # @!classmethods
    module ClassMethods
      # Define a recipe to be run via ChefSpec and used as the subject of this
      # example group. You can specify either a single recipe block or
      # one-or-more recipe names.
      #
      # @param recipe_names [Array<String>] Recipe names to converge for this test.
      # @param block [Proc] Recipe to converge for this test.
      # @example Using a recipe block
      #   describe 'my recipe' do
      #     recipe do
      #       ruby_block 'test'
      #     end
      #     it { is_expected.to run_ruby_block('test') }
      #   end
      # @example Using external recipes
      #   describe 'my recipe' do
      #     recipe 'my_recipe'
      #     it { is_expected.to run_ruby_block('test') }
      #   end
      def recipe(*recipe_names, &block)
        # Keep the actual logic in a let in case I want to define the subject as something else
        let(:chef_run) { chef_runner.converge(*recipe_names, &block) }
        subject { chef_run }
      end

      # Configure ChefSpec to step in to a resource/provider. This will also
      # automatically create ChefSpec matchers for the resource.
      #
      # @overload step_into(name)
      #   @param name [String, Symbol] Name of the resource in snake-case.
      # @overload step_info(resource, resource_name)
      #   @param resource [Class] Resource class to step in to.
      #   @param resource_name [String, Symbol, nil] Name of the given resource in snake-case.
      # @example
      #   describe 'my_lwrp' do
      #     step_into(:my_lwrp)
      #     recipe do
      #       my_lwrp 'test'
      #     end
      #     it { is_expected.to run_ruby_block('test') }
      #   end
      def step_into(name, resource_name=nil)
        resource_class = if name.is_a?(Class)
          name
        else
          Chef::Resource.const_get(Chef::Mixin::ConvertToClassName.convert_to_class_name(name.to_s))
        end
        resource_name ||= Chef::Mixin::ConvertToClassName.convert_to_snake_case(resource_class.name.split('::').last)

        # Figure out the available actions
        resource_class.new(nil, nil).allowed_actions.each do |action|
          define_method("#{action}_#{resource_name}") do |instance_name|
            ChefSpec::Matchers::ResourceMatcher.new(resource_name, action, instance_name)
          end
        end

        before { step_into << resource_name }
      end

      # Define a resource class for use in an example group. By default the
      # :run action will be set as the default.
      #
      # @param name [Symbol] Name for the resource in snake-case.
      # @param options [Hash] Resource options.
      # @option options [Class, Symbol] :parent (Chef::Resource) Parent class
      #   for the resource. If a symbol is given, it corresponds to another
      #   resource defined via this helper.
      # @option options [Boolean] :auto (true) Set the resource name correctly
      #   and use :run as the default action.
      # @param block [Proc] Body of the resource class. Optional.
      # @example
      #   describe MyMixin do
      #     resource(:my_resource) do
      #       include Poise
      #       attribute(:path, kind_of: String)
      #     end
      #     provider(:my_resource)
      #     recipe do
      #       my_resource 'test' do
      #         path '/tmp'
      #       end
      #     end
      #     it { is_expected.to run_my_resource('test').with(path: '/tmp') }
      #   end
      def resource(name, options={}, &block)
        options = {auto: true, parent: Chef::Resource}.merge(options)
        options[:parent] = resources[options[:parent]] if options[:parent].is_a?(Symbol)
        raise Halite::Error.new("Parent class for #{name} is not a class: #{options[:parent].inspect}") unless options[:parent].is_a?(Class)
        # Create the resource class
        resource_class = Class.new(options[:parent]) do
          class_exec(&block) if block
          # Wrap some stuff around initialize because I'm lazy
          if options[:auto]
            old_init = instance_method(:initialize)
            define_method(:initialize) do |*args|
              # Fill in the resource name because I know it
              @resource_name = name.to_sym
              old_init.bind(self).call(*args)
              # ChefSpec doesn't seem to work well with action :nothing
              if @action == :nothing
                @action = :run
                @allowed_actions |= [:run]
              end
            end
          end
        end

        # Store for use up with the parent system
        (metadata['halite_resources'] ||= {})[name.to_sym] = resource_class

        # Automatically step in to our new resource
        step_into(resource_class, name)

        around do |ex|
          # Patch the resource in to Chef
          patch_module(Chef::Resource, name, resource_class) { ex.run }
        end
      end

      # Define a provider class for use in an example group. By default a :run
      # action will be created and load_current_resource will be defined as a
      # no-op.
      #
      # @param name [Symbol] Name for the provider in snake-case.
      # @param options [Hash] Provider options.
      # @option options [Class, Symbol] :parent (Chef::Provider) Parent class
      #   for the provider. If a symbol is given, it corresponds to another
      #   resource defined via this helper.
      # @option options [Boolean] :auto (true) Create action_run and
      #   load_current_resource.
      # @param block [Proc] Body of the provider class. Optional.
      # @example
      #   describe MyMixin do
      #     resource(:my_resource)
      #     provider(:my_resource) do
      #       include Poise
      #       def action_run
      #         ruby_block 'test'
      #       end
      #     end
      #     recipe do
      #       my_resource 'test'
      #     end
      #     it { is_expected.to run_my_resource('test') }
      #     it { is_expected.to run_ruby_block('test') }
      #   end
      def provider(name, options={}, &block)
        options = {auto: true, rspec: true, parent: Chef::Provider}.merge(options)
        options[:parent] = providers[options[:parent]] if options[:parent].is_a?(Symbol)
        raise Halite::Error.new("Parent class for #{name} is not a class: #{options[:parent].inspect}") unless options[:parent].is_a?(Class)
        provider_class = Class.new(options[:parent]) do
          # Pull in RSpec expectations
          if options[:rspec]
            include RSpec::Matchers
            include RSpec::Mocks::ExampleMethods
          end

          if options[:auto]
            # Default blank impl to avoid error
            def load_current_resource
            end

            # Blank action because I do that so much
            def action_run
            end
          end

          class_exec(&block) if block
        end

        # Store for use up with the parent system
        (metadata['halite_providers'] ||= {})[name.to_sym] = provider_class

        around do |ex|
          patch_module(Chef::Provider, name, provider_class) { ex.run }
        end
      end

      # @!visibility private
      def included(klass)
        super
        klass.extend ClassMethods
      end

      protected

      # Find all helper-defined resources in the current context and parents.
      #
      # @return [Hash<Symbol, Class>]
      def resources
        ([self] + parent_groups).reverse.inject({}) do |memo, group|
          memo.update(group.metadata['halite_resources'] || {})
        end
      end

      # Find all helper-defined providers in the current context and parents.
      #
      # @return [Hash<Symbol, Class>]
      def providers
        ([self] + parent_groups).reverse.inject({}) do |memo, group|
          memo.update(group.metadata['halite_providers'] || {})
        end
      end
    end

    extend ClassMethods
  end
end
