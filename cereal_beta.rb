#!/usr/bin/env ruby
require "yaml"

#to do
# cache some FS info so we don't ssh for each serial device
# put back usage and help
# option to delete custom configs
# more cli options (host limiting...)

# config
hostname = `hostname`.chomp

@localhost = ["localhost",hostname,hostname[/^[^.]+/]]
@hosts = ["localhost"]

default_settings = "115200,cs8,-parenb,-cstopb,-hupcl" # 115200,8N1

# load dotfile
dotfile_data = {}
per_device_settings = {}
dotfile_path = File.expand_path("~/.cereal2")
if File.exists? dotfile_path
  dotfile_data = YAML.load_file dotfile_path
end

if dotfile_data["default_serial_flags"]
  default_settings = dotfile_data["default_serial_flags"]
end
if dotfile_data["hosts"]
  @hosts = dotfile_data["hosts"]
end
if dotfile_data["per_device_settings"]
  per_device_settings = dotfile_data["per_device_settings"]
else
  dotfile_data["per_device_settings"] = {}
end

USAGE = "ha, there is no help for alpha spftware!"

(name,settings_from_cmd) = (ARGV)
unless name
  puts USAGE
  raise "bad command syntax"
end

if /^(-H|(hosts|--hosts))$/.match name
  if settings_from_cmd
    # write new list of hosts
    dotfile_data["hosts"] = settings_from_cmd.split(',')
    File.write(dotfile_path, YAML.dump(dotfile_data))
  else
    # print list of hosts
    puts "currently configured to connect to serial devices on the following hosts: #{@hosts.join(",")}"
  end
  exit 0
end

if /^(-d|(default|--default)s?)$/.match name
  if settings_from_cmd
    # write default settings
    dotfile_data["default_serial_flags"] = settings_from_cmd
    File.write(dotfile_path, YAML.dump(dotfile_data))
  else
    # print default settings
    puts default_settings
  end
  exit 0
end

# delete user-set default
if /^(\-D|(delete-default|--delete-default)s?)$/.match name
  dotfile_data.delete("default_serial_flags")
  File.write(dotfile_path, YAML.dump(dotfile_data))
  exit 0
end

def screen_wrapper(device,settings,host=nil)
  # locate device and resolve symlink
  hosts = @hosts
  if host
    hosts = [host]
  end
  tty = nil
  hosts.each do |h|
    host_tty = backtick_wrapper("readlink /dev/#{device}",h).chomp
    if host_tty.length > 0
      tty = host_tty
      host = h
    end
  end
  
  puts "device #{device}"
  if tty
    puts "on #{host} at #{tty}"
  else
    puts "not found"
    exit 6
  end  

  screen_cmd = nil

  # is device open?
  pid = tty2pid(host,tty)
  if pid
    # device is in use, see if we can attach
    puts "in use by pid #{pid}"
    # is device attached?
    if @attached[host].include? pid
      warn "Cannot attach, device already in use by attached screen session #{pid}"
      exit 16
    elsif @detached[host].include? pid
      # re-connect to detached session
      session_id = backtick_wrapper("screen -list | grep '#{pid}\\.' | cut -f2",host).chomp
      puts "connecting to session id #{session_id} on host #{host}"
      ec = 41
      screen_cmd = "screen -r #{session_id}"
    else
      warn "Cannot attach, device already in use by process other than screen: pid #{pid}"
      exit 16
    end
  else
    # device not in use, establist new connection
    screen_cmd = "screen /dev/#{tty} #{settings}"
  end
  
  if localhost?(host)
    ec = system(screen_cmd)
  else
    ec = system("ssh -t #{host} '#{screen_cmd}'")
  end
  exit ec

end

def backtick_wrapper(cmd,host)
  if localhost?(host)
    return `#{cmd}`
  else
    return `ssh #{host} '#{cmd}'`
  end
end

def localhost?(host)
  return true if host.nil?
  return true if @localhost.include?(host)
  false
end

# find existing sessions
attached_cmd = "screen -list | grep Attached | cut -f2 | cut -d'.' -f1"
detached_cmd = "screen -list | grep Detached | cut -f2 | cut -d'.' -f1"
open_device_cmd = "lsof -Fpn /dev/ttyUSB*"

@attached = {}
@detached = {}
@tty2pid = {}

@hosts.each do |host|
  @attached[host] = backtick_wrapper(attached_cmd,host).split
  @detached[host] = backtick_wrapper(detached_cmd,host).split
  tty2pid = {}
  backtick_wrapper(open_device_cmd,host).gsub("\nn"," ").gsub(/^p/,"").split("\n").each do |f|
    (fpid,fname) = f.split
    fname.sub!("/dev/","")
    tty2pid[fname]=fpid
  end
  @tty2pid[host] = tty2pid
end

# get pid using tty
def tty2pid(host,tty)
  alt_tty = backtick_wrapper("readlink /dev/#{tty}",host).chomp
  if (alt_tty.length > 0)
    tty = alt_tty
  end
  @tty2pid[host][tty]
end

# list serial device aliases
if /^(list|-l|--list)$/i.match name
  # check if flag is capitalized
  verbose_listing = true
  if /^(list|-l|--list)$/.match name
    verbose_listing = false
  end
  
  @hosts.each do |host|
    if localhost?(host) and host!='localhost'
      puts "#{host} (localhost)"
    else
      puts host
    end
    ttys = backtick_wrapper(%q{find /dev -maxdepth 1 -type l -ilname "*tty*" | cut -d'/' -f3 | sort -V},host).split    
    # filter out alias names beginning w/ tty
    if !verbose_listing
      ttys.select! { |x| !x.match /^tty/ }
    end

    ttys.each do |tty|
      status = ' '
      pid = tty2pid(host,tty)
      if pid
        case pid
        when *@attached[host]
          status = 'A'
        when *@detached[host]
          status = 'D'
        else
          status = '?'
        end
      end
      # print name of tty w/ status
      puts "#{status}   #{tty}"
    end
  end

  exit 0
end

# determine connection settings
screen_settings = default_settings
settings_from_dotfile = per_device_settings[name]
if settings_from_dotfile
  screen_settings = settings_from_dotfile
end

save = nil
if settings_from_cmd
  screen_settings = settings_from_cmd
  if !settings_from_dotfile
    print "No previous custom settings for this device found. Shall I save new custom settings for this device? (Y/n)? "
    ans = $stdin.gets.chomp
    if (ans.match(/^y(es)?/i) or ans=="")
      save = true
    else
      puts "Continuing without Save"
    end
  elsif settings_from_cmd!=settings_from_dotfile
    print "Found existing custom settings for this device. Shall I overwrite (y/N)? "
    if $stdin.gets.chomp.match(/^y(es)?/i)
      save = true
    else
      puts "Continuing without Save"
    end
  end
end

if save
  dotfile_data["per_device_settings"][name] = screen_settings
  File.write(File.expand_path("~/.cereal"), YAML.dump(conf))
  puts "config saved"
end

screen_wrapper(name,default_settings)
