#cereal
Grrrrreat way to connect to your tty devices so you don't snap. Or crackle. Or, well, you get the idea.

## what does this do?
* Sets up serial console sessions using `screen` to connect to tty devices.
* Saves connection configuration string (baud rate, parity, etc) so you don't have to remember all that nonsense.
* Reattaches `screen` sessions based on the tty name, so you don't have to search for a session name or even remember if you have a session open.
* Lists serial ports and their status. 

## getting started
Use udev rules to make static names (aliases) for your serial ports. I like to use logical names indicating where the port is physically (which rack, which U, which port number, etc) and a second alias using the name of the server or device the serial port is connecting to. This is accomplished using custom udev rules. I've included a excerpted version of my udev rules file to get you started.

## requirements
* Linux host with a lot of serial ports to manage
* ruby
* GNU Screen

## future development ideas
* search for tty devices attached to remote hosts, via ssh (w/ keypair or cm auth only, of course)
* basic support for non-Linux OSes (only when connecting to ttys attached to a remote Linux host; this app doesn't make much sense w/o udev)

