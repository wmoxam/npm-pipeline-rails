require 'rails'
require 'rails/railtie'

module NpmPipelineRails
  module Utils
    module_function

    def log(str)
      ::Rails.logger.debug "[npm-pipeline-rails] #{str}"
    end

    def do_system(commands)
      [*commands].each do |cmd|
        Utils.log "starting '#{cmd}'"
        system cmd
        Utils.log "'#{cmd}' exited with #{$?.exitstatus} status"
        exit $?.exitstatus unless $?.exitstatus == 0
      end
    end

    # Runs a block in the background. When the parent exits, the child
    # will be asked to exit as well.
    def background(name, &blk)
      pid = fork(&blk)

      at_exit do
        Utils.log "Terminating '#{name}' [#{pid}]"
        begin
          Process.kill 'TERM', pid
          Process.wait pid
        rescue Errno::ESRCH, Errno::ECHILD => e
          Utils.log "'#{name}' [#{pid}] already dead (#{e.class})"
        end
      end
    end

    def running?(signature)
      normalized_signature = "[#{signature.slice(0,1)}]#{signature.slice(1, signature.length-1)}"
      !(`ps aux | grep "#{normalized_signature}"`.blank?)
    end
  end

  class Railtie < ::Rails::Railtie
    config.npm = ActiveSupport::OrderedOptions.new
    config.npm.enable_watch = ::Rails.env.development?
    config.npm.build = ['npm run build']
    config.npm.watch = ['npm run start']
    config.npm.watch_signature = ['npm.*start']
    config.npm.install = ['npm install']
    config.npm.install_on_asset_precompile = true

    rake_tasks do |app|
      namespace :assets do
        desc 'Build asset prerequisites using npm'
        task :npm_build do
          if app.config.npm.install_on_asset_precompile
            Utils.do_system app.config.npm.install
          end
          Utils.do_system app.config.npm.build
        end

        task(:precompile).enhance ['npm_build']
      end
    end
    initializer 'npm_pipeline.watch' do |app|
      if app.config.npm.enable_watch && (!::Rails.const_defined?(:Console) && File.basename($0) != "rake")
        Utils.do_system app.config.npm.install if !Utils.running?(app.config.npm.watch_signature.first)
        [*app.config.npm.watch].each_with_index do |cmd, index|
          Utils.background(cmd) { Utils.do_system [cmd] } if !Utils.running?(config.npm.watch_signature[index] || cmd)
        end
      end
    end
  end
end
