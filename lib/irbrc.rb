require 'fileutils'
require 'highline'


module Irbrc
  VERSION = '0.0.1'
  BASE_DIR = [
    Dir.home,
    '.irb/rc',
  ].join File::SEPARATOR


  class << self

    def load_rc
      if rc_path
        init unless File.exists? rc_path
        load rc_path if File.exists? rc_path
      end
    end


    def init
      if File.exists? local_rc
        if rc_path == File.realpath(local_rc)
          # already linked, no-op
        elsif agree("Move existing rc: #{local_rc}")
          File.rename local_rc, rc_path
          link_rc
        else
          link_rc reverse: true
        end
      elsif agree('Create irbrc')
        create_rc unless File.exists? rc_path
        link_rc
      end

      init_global_rc
      git_ignore

      nil
    end


    # add auto-load to ~/.irbrc
    def init_global_rc
      global_rc = [ Dir.home, '.irbrc' ].join File::SEPARATOR
      require_cmd = "require 'irbrc'"

      add_required = if File.exists? global_rc
        add_msg = "Add `#{require_cmd}` to #{global_rc}"
        File.read(global_rc) !~ /\W#{require_cmd}\W/ and agree(add_msg)
      else
        true
      end

      if add_required
        File.open(global_rc, 'a') do |fh|
          fh.write "\n"
          fh.write "# load per project .irbrc\n"
          fh.write "#{require_cmd}\n"
          fh.write "load_rc\n\n"
        end
      end
    end


    def git_ignore
      ignore_path = [
        project_root,
        '.git',
        'info',
        'exclude'
      ].join File::SEPARATOR
      add_required = if File.exists? ignore_path
        msg = "Add .irbrc to #{ignore_path}"
        File.read(ignore_path) !~ /\W\.irbrc\W/ and agree(msg)
      else
        add_required = true
      end

      if add_required
        File.open(ignore_path, 'a') do |fh|
          fh.write "\n.irbrc\n"
        end
      end
    end


    def localize opts = {}
      if File.exists? local_rc
        if opts[:force] or File.realpath(local_rc) == rc_path
          unlink local_rc
        else
          unlink local_rc if agree "Remove local rc: #{local_rc}"
        end
      end

      File.rename rc_path, local_rc unless File.exists? local_rc
    end


    def remove_rc opts = {}
      unlink rc_path, local_rc
    end


    def create_rc opts = {}
      unlink rc_path if opts[:force]

      if File.exists? rc_path
        raise Exception.new "rc file already exists: #{rc_path}"
      end

      FileUtils.mkpath File.dirname rc_path
      File.open(rc_path, 'w') do |fh|
        repo = parse_repo
        fh.write "# IRBRC for #{parse_repo[:source]}:#{repo[:repo]}\n"
        fh.write "\n\n"
      end

      nil
    end


    def link_rc opts = {}
      if opts[:reverse]
        unlink rc_path if opts[:force]
        File.symlink File.realpath(local_rc), rc_path
      else
        unlink local_rc if opts[:force]
        File.symlink rc_path, local_rc
      end

      nil
    end


    def rc_path
      repo = parse_repo

      [
        BASE_DIR,
        repo[:source],
        repo[:repo].sub(/#{File::SEPARATOR}/, '.') + '.rc',
      ].join File::SEPARATOR
    end


    def parse_repo str = nil
      begin
        str = `git remote -v` unless str
      rescue
        # bail
        return nil
      end

      repos = str.split("\n").map(&:split).map do |line|
        source, repo = line[1].split ':'
        source.sub! /^.*@/, ''
        source.sub! /\.(com|org)$/, ''

        {
          source: source,
          repo: repo,
        }
      end.uniq

      if repos.count != 1
        raise Error.new "parse error: #{str}"
      end

      repos.first
    end


    def local_rc
      [
        project_root,
        '.irbrc'
      ].join File::SEPARATOR
    end


    def project_root
      `git rev-parse --show-toplevel`.chomp
    end


    def agree msg
      HighLine.new.agree("#{msg}?  [Y/n]") do |q|
        yield q if block_given?
      end
    end


    def unlink *paths
      paths.select do |path|
        1 == File.unlink(path) if File.exists? path or File.symlink? path
      end
    end


  end
end


# define global function for convenience
define_singleton_method(:load_rc) { Irbrc.load_rc }
