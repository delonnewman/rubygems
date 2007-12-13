#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/installer'

class Gem::Installer
  attr_accessor :gem_dir

  attr_writer :format
  attr_writer :gem_home
  attr_writer :env_shebang
  attr_writer :ignore_dependencies
  attr_writer :format_executable
  attr_writer :security_policy
  attr_writer :spec
  attr_writer :wrappers
end

class TestGemInstaller < RubyGemTestCase

  def setup
    super

    @spec = quick_gem "a"
    @gem = File.join @tempdir, "#{@spec.full_name}.gem"

    util_build_gem @spec
    FileUtils.mv File.join(@gemhome, 'cache', "#{@spec.full_name}.gem"),
                 @tempdir

    @installer = Gem::Installer.new @gem
    @installer.gem_dir = util_gem_dir
    @installer.gem_home = @gemhome
    @installer.spec = @spec
  end

  def util_gem_dir(version = '0.0.2')
    File.join @gemhome, "gems", "a-#{version}" # HACK
  end

  def util_gem_bindir(version = '0.0.2')
    File.join util_gem_dir(version), "bin"
  end

  def util_inst_bindir
    File.join @gemhome, "bin"
  end

  def util_make_exec(version = '0.0.2', shebang = "#!/usr/bin/ruby")
    @spec.executables = ["my_exec"]

    FileUtils.mkdir_p util_gem_bindir(version)
    exec_file = @installer.formatted_program_filename "my_exec"
    exec_path = File.join util_gem_bindir(version), exec_file
    File.open exec_path, 'w' do |f|
      f.puts shebang
    end
  end

  def test_app_script_text
    util_make_exec '0.0.2', ''

    expected = <<-EOF
#!#{Gem.ruby}
#
# This file was generated by RubyGems.
#
# The application 'a' is installed as part of a gem, and
# this file is here to facilitate running it.
#

require 'rubygems'

version = \">= 0\"

if ARGV.first =~ /^_(.*)_$/ and Gem::Version.correct? $1 then
  version = $1
  ARGV.shift
end

gem 'a', version
load 'my_exec'
    EOF

    wrapper = @installer.app_script_text 'my_exec'
    assert_equal expected, wrapper
  end

  def test_build_extensions_none
    use_ui @ui do
      @installer.build_extensions
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    assert !File.exist?('gem_make.out')
  end

  def test_build_extensions_extconf_bad
    @spec.extensions << 'extconf.rb'

    e = assert_raise Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions
      end
    end

    assert_match(/\AERROR: Failed to build gem native extension.$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    gem_make_out = File.join @gemhome, 'gems', @spec.full_name, 'gem_make.out'
    expected = <<-EOF
#{Gem.ruby} extconf.rb
#{Gem.ruby}: No such file or directory -- extconf.rb (LoadError)
    EOF

    assert_equal expected, File.read(gem_make_out)
  end

  def test_build_extensions_unsupported
    @spec.extensions << nil

    e = assert_raise Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions
      end
    end

    assert_match(/^No builder for extension ''$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    assert_equal "No builder for extension ''\n", File.read('gem_make.out')
  ensure
    FileUtils.rm_f 'gem_make.out'
  end

  def test_ensure_dependency
    dep = Gem::Dependency.new 'a', '>= 0.0.2'
    assert @installer.ensure_dependency(@spec, dep)

    dep = Gem::Dependency.new 'b', '> 0.0.2'
    e = assert_raise Gem::InstallError do
      @installer.ensure_dependency @spec, dep
    end

    assert_equal 'a requires b (> 0.0.2)', e.message
  end

  def test_expand_and_validate_gem_dir
    @installer.gem_dir = '/nonexistent'
    expanded_gem_dir = @installer.send(:expand_and_validate_gem_dir)
    if win_platform?
      expected = File.join(Config::CONFIG['bindir'][0..2], 'nonexistent').downcase
      expanded_gem_dir = expanded_gem_dir.downcase
    else
      expected = '/nonexistent'
    end

    assert_equal expected, expanded_gem_dir
  end

  def test_extract_files
    format = Object.new
    def format.file_entries
      [[{'size' => 7, 'mode' => 0400, 'path' => 'thefile'}, 'thefile']]
    end

    @installer.format = format

    @installer.extract_files

    assert_equal 'thefile', File.read(File.join(util_gem_dir, 'thefile'))
  end

  def test_extract_files_bad_dest
    @installer.gem_dir = 'somedir'
    @installer.format = nil
    e = assert_raise ArgumentError do
      @installer.extract_files
    end

    assert_equal 'format required to extract from', e.message
  end

  def test_extract_files_relative
    format = Object.new
    def format.file_entries
      [[{'size' => 10, 'mode' => 0644, 'path' => '../thefile'}, '../thefile']]
    end

    @installer.format = format

    e = assert_raise Gem::InstallError do
      @installer.extract_files
    end

    assert_equal "attempt to install file into \"../thefile\" under #{util_gem_dir.inspect}",
                 e.message
    assert_equal false, File.file?(File.join(@tempdir, '../thefile')),
                 "You may need to remove this file if you broke the test once"
  end

  def test_extract_files_absolute
    format = Object.new
    def format.file_entries
      [[{'size' => 8, 'mode' => 0644, 'path' => '/thefile'}, '/thefile']]
    end

    @installer.format = format

    e = assert_raise Gem::InstallError do
      @installer.extract_files
    end

    assert_equal 'attempt to install file into "/thefile"', e.message
    assert_equal false, File.file?(File.join('/thefile')),
                 "You may need to remove this file if you broke the test once"
  end

  def test_generate_bin_bindir
    @installer.wrappers = true

    @spec.executables = ["my_exec"]
    @spec.bindir = '.'

    exec_file = @installer.formatted_program_filename "my_exec"
    exec_path = File.join util_gem_dir(@spec.version), exec_file
    File.open exec_path, 'w' do |f|
      f.puts '#!/usr/bin/ruby'
    end

    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)
    assert_equal(0100755, File.stat(installed_exec).mode) unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_scripts
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)
    assert_equal(0100755, File.stat(installed_exec).mode) unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_scripts_format
    @installer.format_executable = true
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'foo-my_exec-bar'
    assert_equal true, File.exist?(installed_exec)
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_scripts_format_disabled
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'my_exec'
    assert_equal true, File.exist?(installed_exec)
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_scripts_install_dir
    @installer.wrappers = true
    @spec.executables = ["my_exec"]

    gem_dir = File.join "#{@gemhome}2", 'gems', @spec.full_name
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, "my_exec"), 'w' do |f|
      f.puts "#!/bin/ruby"
    end

    @installer.gem_home = "#{@gemhome}2"
    @installer.gem_dir = gem_dir

    @installer.generate_bin

    installed_exec = File.join("#{@gemhome}2", 'bin', 'my_exec')
    assert_equal true, File.exist?(installed_exec)
    assert_equal(0100755, File.stat(installed_exec).mode) unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_scripts_no_execs
    @installer.wrappers = true
    @installer.generate_bin
    assert_equal false, File.exist?(util_inst_bindir)
  end

  def test_generate_bin_scripts_no_perms
    @installer.wrappers = true
    util_make_exec

    Dir.mkdir util_inst_bindir
    File.chmod 0000, util_inst_bindir

    assert_raises Gem::FilePermissionError do
      @installer.generate_bin
    end

  ensure
    File.chmod 0700, util_inst_bindir unless $DEBUG
  end

  def test_generate_bin_symlinks
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.symlink?(installed_exec)
    assert_equal(File.join(util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))
  end

  def test_generate_bin_symlinks_no_execs
    @installer.wrappers = false
    @installer.generate_bin
    assert_equal false, File.exist?(util_inst_bindir)
  end

  def test_generate_bin_symlinks_no_perms
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Dir.mkdir util_inst_bindir
    File.chmod 0000, util_inst_bindir

    assert_raises Gem::FilePermissionError do
      @installer.generate_bin
    end

  ensure
    File.chmod 0700, util_inst_bindir unless $DEBUG
  end

  def test_generate_bin_symlinks_update_newer
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec '0.0.3'
    @installer.gem_dir = File.join util_gem_dir('0.0.3')
    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_bindir('0.0.3'), "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlinks_update_older
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))

    spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.1"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec '0.0.1'
    @installer.gem_dir = util_gem_dir('0.0.1')
    @installer.spec = spec

    @installer.generate_bin

    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir('0.0.2'), "bin", "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink not moved")
  end

  def test_generate_bin_symlinks_update_remove_wrapper
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    @installer.wrappers = false
    util_make_exec '0.0.3'
    @installer.gem_dir = util_gem_dir '0.0.3'
    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir('0.0.3'), "bin", "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlinks_win32
    old_win_platform = Gem.win_platform?
    Gem.win_platform = true
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    use_ui @ui do
      @installer.generate_bin
    end

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)

    assert_match(/Unable to use symlinks on Windows, installing wrapper/i,
                 @ui.error)

    wrapper = File.read installed_exec
    assert_match(/generated by RubyGems/, wrapper)
  ensure
    Gem.win_platform = old_win_platform
  end

  def test_generate_bin_uses_default_shebang
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec

    @installer.generate_bin

    default_shebang = File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name'])
    shebang_line = open("#{@gemhome}/bin/my_exec") { |f| f.readlines.first }
    assert_match(/\A#!/, shebang_line)
    assert_match(/#{default_shebang}/, shebang_line)
  end

  def test_initialize
    spec = quick_gem 'a' do |s| s.platform = Gem::Platform.new 'mswin32' end
    gem = File.join @tempdir, "#{spec.full_name}.gem"

    util_build_gem spec
    FileUtils.mv File.join(@gemhome, 'cache', "#{spec.full_name}.gem"),
                 @tempdir

    installer = Gem::Installer.new gem

    assert_equal File.join(@gemhome, 'gems', spec.full_name), installer.gem_dir
  end

  def test_install
    util_setup_gem

    use_ui @ui do
      assert_equal @spec, @installer.install
    end

    gemdir = File.join @gemhome, 'gems', @spec.full_name
    assert File.exist?(gemdir)

    exe = File.join(gemdir, 'bin', 'executable')
    assert File.exist?(exe)
    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode unless win_platform?

    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    assert File.exist?(File.join(gemdir, 'ext', 'a', 'Rakefile'))

    spec_file = File.join(@gemhome, 'specifications',
                          "#{@spec.full_name}.gemspec")

    assert_equal spec_file, @spec.loaded_from
    assert File.exist?(spec_file)
  end

  def test_install_bad_gem
    gem = nil

    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end
      gem = File.join @tempdir, "#{@spec.full_name}.gem"
    end

    gem_data = File.open gem, 'rb' do |fp| fp.read 1024 end
    File.open gem, 'wb' do |fp| fp.write gem_data end

    e = assert_raise Gem::InstallError do
      use_ui @ui do
        @installer = Gem::Installer.new gem
        @installer.install
      end
    end

    assert_equal "invalid gem format for #{gem}", e.message
  end

  def test_install_check_dependencies
    @spec.add_dependency 'b', '> 5'
    util_setup_gem

    use_ui @ui do
      assert_raise Gem::InstallError do
        @installer.install
      end
    end
  end

  def test_install_force
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required, :force => true
      installer.install
    end

    gem_dir = File.join(@gemhome, 'gems', 'old_ruby_required-0.0.1')
    assert File.exist?(gem_dir)
  end

  def test_install_ignore_dependencies
    @spec.add_dependency 'b', '> 5'
    util_setup_gem
    @installer.ignore_dependencies = true

    use_ui @ui do
      assert_equal @spec, @installer.install
    end

    gemdir = File.join @gemhome, 'gems', @spec.full_name
    assert File.exist?(gemdir)

    exe = File.join(gemdir, 'bin', 'executable')
    assert File.exist?(exe)
    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode unless win_platform?
    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    assert File.exist?(File.join(@gemhome, 'specifications',
                                 "#{@spec.full_name}.gemspec"))
  end

  def test_install_missing_dirs
    FileUtils.rm_f File.join(Gem.dir, 'cache')
    FileUtils.rm_f File.join(Gem.dir, 'docs')
    FileUtils.rm_f File.join(Gem.dir, 'specifications')

    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end
      gem = File.join @tempdir, "#{@spec.full_name}.gem"

      @installer.install
    end

    File.directory? File.join(Gem.dir, 'cache')
    File.directory? File.join(Gem.dir, 'docs')
    File.directory? File.join(Gem.dir, 'specifications')

    assert File.exist?(File.join(@gemhome, 'cache', "#{@spec.full_name}.gem"))
    assert File.exist?(File.join(@gemhome, 'specifications',
                                 "#{@spec.full_name}.gemspec"))
  end

  def test_install_with_message
    @spec.post_install_message = 'I am a shiny gem!'

    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end

      @installer.install
    end

    assert_match %r|I am a shiny gem!|, @ui.output
  end

  def test_install_writable
    util_setup_gem

    orig_mode = File.stat(Gem.dir).mode
    File.chmod 0000, Gem.dir

    e = assert_raise Gem::FilePermissionError do
      @installer.install
    end

    assert_equal "You don't have write permissions into the #{@gemhome} directory.",
                 e.message
  ensure
    File.chmod orig_mode, Gem.dir
  end

  def test_install_wrong_ruby_version
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required
      e = assert_raise Gem::InstallError do
        installer.install
      end
      assert_equal 'old_ruby_required requires Ruby version = 1.4.6',
                   e.message
    end
  end

  def test_install_wrong_rubygems_version
    spec = quick_gem 'old_rubygems_required', '0.0.1' do |s|
      s.required_rubygems_version = '< 0.0.0'
    end

    util_build_gem spec

    gem = File.join @gemhome, 'cache', "#{spec.full_name}.gem"

    use_ui @ui do
      @installer = Gem::Installer.new gem
      e = assert_raise Gem::InstallError do
        @installer.install
      end
      assert_equal 'old_rubygems_required requires RubyGems version < 0.0.0',
                   e.message
    end
  end

  def test_installation_satisfies_dependency_eh
    dep = Gem::Dependency.new 'a', '>= 0.0.2'
    assert @installer.installation_satisfies_dependency?(dep)

    dep = Gem::Dependency.new 'a', '> 0.0.2'
    assert ! @installer.installation_satisfies_dependency?(dep)
  end

  def test_shebang
    util_make_exec '0.0.2', "#!/usr/bin/ruby"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_arguments
    util_make_exec '0.0.2', "#!/usr/bin/ruby -ws"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_empty
    util_make_exec '0.0.2', ''

    shebang = @installer.shebang 'my_exec'
    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env
    util_make_exec '0.0.2', "#!/usr/bin/env ruby"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env_arguments
    util_make_exec '0.0.2', "#!/usr/bin/env ruby -ws"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_env_shebang
    util_make_exec '0.0.2', ''
    @installer.env_shebang = true

    shebang = @installer.shebang 'my_exec'
    assert_equal "#!/usr/bin/env ruby", shebang
  end

  def test_shebang_nested
    util_make_exec '0.0.2', "#!/opt/local/ruby/bin/ruby"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_nested_arguments
    util_make_exec '0.0.2', "#!/opt/local/ruby/bin/ruby -ws"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version
    util_make_exec '0.0.2', "#!/usr/bin/ruby18"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_arguments
    util_make_exec '0.0.2', "#!/usr/bin/ruby18 -ws"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version_env
    util_make_exec '0.0.2', "#!/usr/bin/env ruby18"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_env_arguments
    util_make_exec '0.0.2', "#!/usr/bin/env ruby18 -ws"

    shebang = @installer.shebang 'my_exec'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_unpack
    util_setup_gem

    dest = File.join @gemhome, 'gems', @spec.full_name

    @installer.unpack dest

    assert File.exist?(File.join(dest, 'lib', 'code.rb'))
    assert File.exist?(File.join(dest, 'bin', 'executable'))
  end

  def test_write_spec
    spec_dir = File.join @gemhome, 'specifications'
    spec_file = File.join spec_dir, "#{@spec.full_name}.gemspec"
    FileUtils.rm spec_file
    assert !File.exist?(spec_file)

    @installer.spec = @spec
    @installer.gem_home = @gemhome

    @installer.write_spec

    assert File.exist?(spec_file)
    assert_equal @spec, eval(File.read(spec_file))
  end

  def old_ruby_required
    spec = quick_gem 'old_ruby_required', '0.0.1' do |s|
      s.required_ruby_version = '= 1.4.6'
    end

    util_build_gem spec

    File.join @gemhome, 'cache', "#{spec.full_name}.gem"
  end

  def util_setup_gem
    @spec.files = File.join('lib', 'code.rb')
    @spec.executables << 'executable'
    @spec.extensions << File.join('ext', 'a', 'mkrf_conf.rb')

    Dir.chdir @tempdir do
      FileUtils.mkdir_p 'bin'
      FileUtils.mkdir_p 'lib'
      FileUtils.mkdir_p File.join('ext', 'a')
      File.open File.join('bin', 'executable'), 'w' do |f| f.puts '1' end
      File.open File.join('lib', 'code.rb'), 'w' do |f| f.puts '1' end
      File.open File.join('ext', 'a', 'mkrf_conf.rb'), 'w' do |f|
        f << <<-EOF
          File.open 'Rakefile', 'w' do |rf| rf.puts "task :default" end
        EOF
      end

      use_ui @ui do
        FileUtils.rm @gem
        Gem::Builder.new(@spec).build
      end
    end

    @installer = Gem::Installer.new @gem
  end

end

