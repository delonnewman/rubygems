#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require 'test/gemutilities'

class TestKernel < RubyGemTestCase

  def setup
    super

    @old_path = $:.dup

    util_fake_gems
  end

  def teardown
    super

    $:.replace @old_path
  end

  def test_gem
    assert gem('a', '= 0.0.1'), "Should load"
    assert $:.any? { |p| %r{a-0.0.1/lib} =~ p }
    assert $:.any? { |p| %r{a-0.0.1/bin} =~ p }
  end

  def test_gem_redundent
    assert gem('a', '= 0.0.1'), "Should load"
    assert ! gem('a', '= 0.0.1'), "Should not load"
    assert_equal 1, $:.select { |p| %r{a-0.0.1/lib} =~ p }.size
    assert_equal 1, $:.select { |p| %r{a-0.0.1/bin} =~ p }.size
  end

  def test_gem_overlapping
    assert gem('a', '= 0.0.1'), "Should load"
    assert ! gem('a', '>= 0.0.1'), "Should not load"
    assert_equal 1, $:.select { |p| %r{a-0.0.1/lib} =~ p }.size
    assert_equal 1, $:.select { |p| %r{a-0.0.1/bin} =~ p }.size
  end

  def test_gem_conflicting
    assert gem('a', '= 0.0.1'), "Should load"

    ex = assert_raise Gem::Exception do
      gem 'a', '= 0.0.2'
    end

    assert_match(/activate a \(= 0\.0\.2\)/, ex.message)
    assert_match(/activated a-0\.0\.1/, ex.message)

    assert $:.any? { |p| %r{a-0.0.1/lib} =~ p }
    assert $:.any? { |p| %r{a-0.0.1/bin} =~ p }
    assert ! $:.any? { |p| %r{a-0.0.2/lib} =~ p }
    assert ! $:.any? { |p| %r{a-0.0.2/bin} =~ p }
  end

end

