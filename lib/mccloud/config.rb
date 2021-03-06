require 'mccloud/config/mccloud'
require 'mccloud/config/provider'
require 'mccloud/config/template'
require 'mccloud/config/keypair'
require 'mccloud/config/collection'
require 'mccloud/template'
require 'mccloud/keypair'


module Mccloud
  class Config

    #    include ::Mccloud::Logger

    attr_accessor :mccloud

    attr_reader :env

    attr_accessor :vms,:lbs,:stacks,:ips,:keystores

    attr_accessor :providers
    
    attr_accessor :templates,:keypairs

    def initialize(options)
      @env=options[:env]
      env.logger.info("config") { "Initializing empty list of vms,lbs,stacks, ips in config" }

      @vms=Hash.new;@lbs=Hash.new;@stacks=Hash.new;@ips=Hash.new; @keystores=Hash.new; @keypairs=Hash.new;

      @providers=Hash.new; @templates=Hash.new
    end

    def define()
      config=OpenStruct.new

      # These don't depend on a provider
      config.mccloud=::Mccloud::Config::Mccloud.new(self)

      # Assign templates
      config.template=::Mccloud::Config::Template.new(self)
      @templates=config.template.components

      # Assign keypairs
      config.keypair=::Mccloud::Config::Keypair.new(self)
      @keypairs=config.keypair.components

      # Assign providers
      config.provider=::Mccloud::Config::Provider.new(self)
      @providers=config.provider.components

      # These components depend on a provider, so we try to guess it frst
      config.vm=::Mccloud::Config::Collection.new("vm",self)
      config.lb=::Mccloud::Config::Collection.new("lb",self)
      config.ip=::Mccloud::Config::Collection.new("ip",self)
      config.stack=::Mccloud::Config::Collection.new("stack",self)
      config.keystore=::Mccloud::Config::Collection.new("keystore",self)

      # Process config file
      yield config

      @mccloud=config.mccloud

    end

    # We put a long name to not clash with any function in the Mccloud file itself
    def load_mccloud_config()
      mccloud_configurator=self
      begin
        mccloudfile=File.read(File.join(Dir.pwd,"Mccloudfile"))
        mccloudfile.gsub!("Mccloud::Config.run","mccloud_configurator.define")
        #        http://www.dan-manges.com/blog/ruby-dsls-instance-eval-with-delegation
        instance_eval(mccloudfile)
      rescue LoadError => e
        env.ui.error "Error loading configfile - Sorry"
        env.ui.error e.message
        exit -1
      rescue NoMethodError => e
        env.ui.error "Some method got an error in the configfile - Sorry"
        env.ui.error $!
        env.ui.error e.message
        exit -1
      rescue Error => e
        env.ui.error "Error processing configfile - Sorry"
        env.ui.error e.message
        exit -1
      end
      return self
    end

    def load_templates()
      # Read templates from templatepath
      env.ui.info "Loading templates from template path"
      paths=env.config.mccloud.template_path

      expanded_paths=paths.collect { |t| t==:internal ?  File.join(File.dirname(__FILE__),"..","..","templates") : t }

      valid_paths=expanded_paths.collect { |path|
        if File.exists?(path) && File.directory?(path)
          env.logger.info "Template path #{path} exists"
          File.expand_path(path)
        else
          env.logger.info "Template path #{path} does not exist, skipping"
          return nil
        end
      }

      # Create a dummy config
      config=OpenStruct.new
      config.env=env
      config.template=::Mccloud::Config::Template.new(config)

      # For all paths that exist
      valid_paths.each do |path|

        # Read subdirectories
        definition_dirs=Dir[File.join(path,"**")].reject{|d| not File.directory?(d)}
        definition_dirs.each do |dir|
          definition_file=File.join(dir,"definition.rb")
          if File.exists?(definition_file)
            definition=File.read(definition_file)
            env.logger.info(definition)
            config.basedir=File.dirname(definition_file)
            begin
              config.instance_eval(definition)
            rescue NameError => ex
              env.ui.error("NameError reading template from file #{definition_file} #{ex}")
            rescue Exception => ex
              env.ui.error("Error reading template from file #{definition_file}#{ex}")
            end
          else
            env.logger.info "#{definition_file} not found"
          end
        end
      end
      env.config.templates.merge!(config.template.components)
    end

    def load_vms()
      # Read templates from templatepath
      env.ui.info "Loading vms from vm path"
      paths=env.config.mccloud.vm_path

      valid_paths=paths.collect { |path|
        if File.exists?(path) && File.directory?(path)
          env.logger.info "VM path #{path} exists"
          File.expand_path(path)
        else
          env.logger.info "VM #{path} does not exist, skipping"
          return nil
        end
      }

      # Create a dummy config
      config=OpenStruct.new
      config.env=env
      config.vm=::Mccloud::Config::Collection.new("vm",self)

      # For all paths that exist
      valid_paths.compact.each do |path|

        # Read definitions
        Dir.new(path).each do |definition|
          definition_file=File.join(path,definition)
          if definition_file.end_with?(".rb")
            if File.exists?(definition_file)
              definition=File.read(definition_file)
              env.logger.debug(definition)
              begin
                config.instance_eval(definition)
              rescue NameError => ex
                env.ui.error("NameError reading vm from file #{definition_file} #{ex}")
              rescue Exception => ex
                env.ui.error("Error reading vm from file #{definition_file}#{ex}")
              end
            else
              env.logger.info "#{definition_file} not found"
            end
          end
        end
        env.config.vms.merge!(config.vm.components)
      end
    end

    def stackfilter
      vmfilter=self.filter
      filter=vmfilter.gsub!(/[^[:alnum:]]/, '')
      return filter
    end

    def filter()
      mcfilter=Array.new
      if !@prefix.nil?
        mcfilter << @prefix
      end
      if @environment!=""
        mcfilter << @environment
      end
      if @identity!=""
        mcfilter << @identity
      end
      full_filter=mcfilter.join(@delimiter)
      if full_filter.length>0
        full_filter=full_filter+@delimiter
      end
      return full_filter

    end



  end #End Class
end #End Module
