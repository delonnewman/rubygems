require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/source_info_cache'
require 'rubygems/dependency_fetcher'

class Gem::Commands::FetchCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'fetch', 'Download a gem and place it in the current directory'

    add_bulk_threshold_option
    add_proxy_option
    add_source_option

    add_version_option
    add_platform_option
    add_prerelease_option

    add_option '-y', '--include-dependencies',
               'Fetch the required dependent gems.' do |value, options|
			options[:include_dependencies] = true
		end
    add_option '-t', '--target-dir DIR',
							 'Directory to download gems.',
							 ' for use with --include-dependencies' do |value, options|
			options[:target_dir] = File.expand_path(value)
		end
  end

  def arguments # :nodoc:
    'GEMNAME       name of gem to download'
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}'"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def execute
    version = options[:version] || Gem::Requirement.default
    all = Gem::Requirement.default != version

    gem_names = get_all_gem_names

    gem_names.each do |gem_name|
      dep = Gem::Dependency.new gem_name, version
      dep.prerelease = options[:prerelease]

      specs_and_sources = Gem::SpecFetcher.fetcher.fetch(dep, all, true,
                                                         dep.prerelease?)

      specs_and_sources, errors =
        Gem::SpecFetcher.fetcher.fetch_with_errors(dep, all, true,
                                                   dep.prerelease?)

      spec, source_uri = specs_and_sources.sort_by { |s,| s.version }.last

      if spec.nil? then
        show_lookup_failure gem_name, version, errors
        next
      end

			if options[:include_dependencies] then

				# TODO: If given dir does not exist defaults to gems system cache.
				# This is something to change in Gem::DependencyFetcher 
				dir = options[:target_dir] || Dir.pwd

				f = Gem::DependencyFetcher.new :install_dir => File.expand_path(dir)
				f.fetch gem_name, version

        f.fetched_gems.each do |spec|
          say "Successfully fetched #{spec.full_name}"
        end

	      say "Downloaded #{spec.full_name} and it's dependencies to #{dir}"

			else
	
	      path = Gem::RemoteFetcher.fetcher.download spec, source_uri
	      FileUtils.mv path, spec.file_name
	
	      say "Downloaded #{spec.full_name}"

			end
    end
  end

end

