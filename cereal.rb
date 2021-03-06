#!/usr/bin/env ruby
require "yaml"

USAGE = "usage: #{$0} ttyName [tty,config,string]
\t#{$0} -l|-L|-d [conf]|-D|-h"

# default_settings = "" # use screen's defaults
# default_settings = "9600,-parenb,-cstopb,-hupcl"" # 9600,8N1
default_settings = "115200,cs8,-parenb,-cstopb,-hupcl" # 115200,8N1

(name,settings_from_cmd) = (ARGV)
unless name
  puts USAGE
  raise "bad command syntax"
end

if /^(help|-h|--help|-\?)$/.match name
  puts USAGE
  puts
  puts "In default case, connects to named tty, optionally using setting string
\t(settings must use GNU screen's syntax for serial config)"
  puts
  puts "-l|--list  print list of tty symlinks in /dev with name not matching /^tty/"
  puts "-L|--List  print list of all tty symlinks in /dev"
  puts "-d [conf]  print default serial conf, or set user default conf (saved in dotfile)"
  puts "-D         delete user default conf, revert to hardcoded value"
  puts "-h|--help  print this help"
  puts
  puts "Also see `man screen` for screen usage"
  exit 1
end

# get current status of open ttys
attached = `screen -list | grep Attached | cut -f2 | cut -d'.' -f1`.split
detached = `screen -list | grep Detached | cut -f2 | cut -d'.' -f1`.split

@tty2pid = {}
`lsof -Fpn /dev/ttyUSB*`.gsub("\nn"," ").gsub(/\nf\w+/,"").gsub(/^p/,"").split("\n").each do |f|
  (fpid,fname) = f.split
  fname.sub!("/dev/","")
  @tty2pid[fname]=fpid
end

# get pid using tty
def tty2pid(tty)
  if File.symlink? "/dev/#{tty}"
    tty = File.readlink "/dev/#{tty}"
  end
  @tty2pid[tty]
end

# list serial device aliases
if /^(list|-l|--list)$/i.match name
  ttys = `find /dev -maxdepth 1 -type l -ilname "*tty*" | cut -d'/' -f3 | sort -V`.split

  # unless flag is capitalized, filter out alias names beginning w/ tty
  if /^(list|-l|--list)$/.match name
    ttys.select! { |x| !x.match /^tty/ }
  end

  ttys.each do |tty|
    status = ' '
    pid = tty2pid(tty)
    if pid
      case pid
      when *attached
        status = 'A'
      when *detached
        status = 'D'
      else
        status = '?'
      end
    end
    # print name of tty w/ status
    puts "#{status}   #{tty}"
  end

  exit 0
end

# load dotfile
conf = {}
if File.exists? File.expand_path("~/.cereal")
  conf = YAML.load_file File.expand_path("~/.cereal")
  if conf["CEREAL/DEFAULT/SETTINGS"]
    default_settings = conf["CEREAL/DEFAULT/SETTINGS"]
  end
end

if /^(-d|(default|--default)s?)$/.match name
  if settings_from_cmd
    # write default settings
    conf["CEREAL/DEFAULT/SETTINGS"] = settings_from_cmd
    File.write(File.expand_path("~/.cereal"), YAML.dump(conf))
  else
    # print default settings
    puts default_settings
  end
  exit 0
end

# delete user-set default
if /^(\-D|(delete-default|--delete-default)s?)$/.match name
  conf.delete("CEREAL/DEFAULT/SETTINGS")
  File.write(File.expand_path("~/.cereal"), YAML.dump(conf))
  exit 0
end

tty_name = nil
dev_is_alias = false
# check if device exists, is a tty
unless File.exists? "/dev/#{name}"
  raise "device /dev/#{name} does not exist"
end

if File.symlink? "/dev/#{name}"
  tty_name = File.readlink "/dev/#{name}"
  dev_is_alias = true
else
  tty_name = File.basename "/dev/#{name}"
end

unless /^tty/.match tty_name
  raise "device /dev/#{name} does not appear to be a tty device"
end

settings_from_dotfile = conf[name]

settings = nil
save = nil
if settings_from_cmd
  settings = settings_from_cmd
  if !settings_from_dotfile
    # don't save settings for kernel named devices, names are too unstable
    if dev_is_alias
      save = true
    end
  elsif settings_from_cmd!=settings_from_dotfile
    puts "Serial settings: #{settings_from_cmd}"
    puts "Saved serial settings: #{settings_from_dotfile}"
    print "Shall I save new settings to disk (y/N)? "
    if $stdin.gets.chomp.match(/^y(es)?/i)
      print "Saving config... "
      save = true
    else
      puts "Continuing without Save"
    end
  end
elsif settings_from_dotfile
  settings = settings_from_dotfile
else
  settings = default_settings
end

if save
  conf[name] = settings
  File.write(File.expand_path("~/.cereal"), YAML.dump(conf))
  puts "config saved"
end

# try to connect to existing session, if found
open_tty = tty2pid tty_name
if open_tty
  if (attached.include? open_tty)
    puts "/dev/#{name} already in use by attached screen session #{open_tty}"
    exit 0
  elsif (detached.include? open_tty)
    print "/dev/#{name} in use by detached screen session #{open_tty}, attach to this session (Y/n)? "
    $stdin.gets.chomp.match(/^n/i) and exit 0
    session = `screen -list | grep '#{open_tty}\\.' | cut -f2`.chomp
    cmd = "screen -r #{session}"
    puts "Connecting with command: #{cmd}"
    system(cmd)
    exit 0
  else
    puts "/dev/#{name} already in use by process other than screen: pid #{open_tty}"
    exit 0
  end
end

# start new screen session
cmd = "screen /dev/#{name} #{settings}"
puts "Connecting with command: #{cmd}"
system(cmd)

