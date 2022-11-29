#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2018 Harald Sitter <sitter@kde.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 3 of
# the License or any later version accepted by the membership of
# KDE e.V. (or its successor approved by the membership of KDE
# e.V.), which shall act as a proxy defined in Section 14 of
# version 3 of the license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'fileutils'
require 'pathname'
require 'tmpdir'

require 'tty/command'

ENV['KF5_SNAP_WRAPPING'] = '1'

# used to find library paths for the arch we are building on
gnu_arch_map = {amd64: "x86_64", arm64: "aarch64"}
gnu_arch = gnu_arch_map[ENV["SNAP_ARCH"].to_sym]

root = Pathname.new(ENV["SNAPCRAFT_STAGE"]).parent.to_s

# qmlcachegen for reasons beyond me is not actually an imported target but
# set as a variable and then directly passed into execute_process.
STATIC_EXES = [
  "#{root}/parts/kf5/install/usr/bin/qmlcachegen"
].freeze

# qmake has a hack applied by debian where they actually hijack the symlink
# sequence and direct it to some wrapper script which hardcodes paths. Don't
# use this and instead force symlinks to go to the correct helper.
SHODDY_SYMLINK_MANGLER = {
  "#{gnu_arch}-linux-gnu-qmake" => 'qmake'
}

configs = []
Dir.chdir("#{root}/parts/#{ARGV[0]}/install/usr/lib/#{gnu_arch}-linux-gnu/cmake") do
  Dir.glob('*/*Config.cmake').each do |config_file|
    config = config_file.split('/')[-1]
    configs << config.sub('Config.cmake', '')
  end
end

wrapped_exes = []

configs.each do |config|
  warn "config... #{config}"
  Dir.mktmpdir do |tmpdir|
    File.write("#{tmpdir}/CMakeLists.txt", <<-EOF)
cmake_minimum_required(VERSION 3.0)

set(imported_exec_targets)
macro(add_executable)
    message("args ${ARGN}")
    set(args "${ARGN}")
    list(FIND args "IMPORTED" is_imported)
    # Don't use IN_LIST so we don't have to meddle with policies.
    if(is_imported GREATER -1)
        list(LENGTH args len)
        list(GET args 0 name)
        list(APPEND imported_exec_targets ${name})
        message("  is imported ${name}")
    endif()
    _add_executable(${ARGN})
endmacro()

find_package(#{config} REQUIRED NO_MODULE)

file(WRITE "${CMAKE_BINARY_DIR}/import.txt" "")
message("imported_exec_targets ${imported_exec_targets}")
# IMPORTED_LOCATION_DEBIAN
foreach(target IN LISTS imported_exec_targets)
    get_target_property(location ${target} IMPORTED_LOCATION)
    if(NOT location)
        get_target_property(configs ${target} IMPORTED_CONFIGURATIONS)
        foreach(config IN LISTS configs)
            message("t: ${target} ... trying config ${config}")
            get_target_property(location ${target} "IMPORTED_LOCATION_${config}")
        endforeach()
    endif()
    message("t: ${target} => ${location}")
    message("======================")
    file(APPEND "${CMAKE_BINARY_DIR}/import.txt" "${location};")
#   print_target_properties(${target})
endforeach()
EOF

    # TODO: bugged https://phabricator.kde.org/D17234
    next if config.downcase.include?('notifyconfig')
    # meta configs, not to be run without components
    next if config.downcase == 'qt5'
    next if config.downcase == 'kf5'

    cmd = TTY::Command.new
    # FIXME: probably best to ignore errors, or log them somewhere but continue all the same
    if cmd.run!('cmake', '.', "-DCMAKE_FIND_ROOT_PATH=#{Dir.pwd}", chdir: tmpdir).failure?
        puts "Warning: cmake fail config... #{config}"
    end

    exes = File.read("#{tmpdir}/import.txt").strip.split(';')
    exes += STATIC_EXES
    exes.each do |exe|
      warn "exe... #{exe}"
      # FIXME: maybe realname it first, in case there's a symlink?
      next if wrapped_exes.include?(exe)

      orig_exe = "#{exe}.orig"
      if File.exist?(orig_exe) # already created elsewhere?
        warn "#{exe} already exists (unexpectedly); no wrapping is being done!"
        next
      end

      # We move the orig file to .orig, replace it with our wrapper and symlink
      # back up.
      # This allows qtchooser to have the correct execname and qapplications to
      # still be in the correct appdir (e.g. usr/bin/).
      # foo ->wraps-> snap-sdk-wrappers/foo ->symlinks-> foo.orig

      FileUtils.mv(exe, orig_exe, verbose: true)

      if File.symlink?(orig_exe)
        target = File.readlink(orig_exe)
        basename = File.basename(target)
        mangle = SHODDY_SYMLINK_MANGLER[basename]
        next unless mangle

        mangled_target = "#{File.dirname(target)}/#{mangle}"
        FileUtils.rm(orig_exe, verbose: true)
        FileUtils.ln_s(mangled_target, orig_exe, verbose: true)
      end

      basename = File.basename(exe)
      dir = File.dirname(exe)
      wrapped_dir = "#{dir}/snap-sdk-wrappers"
      wrapped_exe = "#{wrapped_dir}/#{basename}"
      FileUtils.mkpath(wrapped_dir, verbose: true)
      FileUtils.ln_s("../#{basename}.orig", wrapped_exe, verbose: true)

      File.write(exe, <<-WRAPPER)
#!/bin/bash

# Only wrap the execution iff we aren't currently in the process of wrapping,
# otherwise we'd break cmake running during the build as the environment
# for the wrap is not actually valid yet.
if [ -z "$KF5_SNAP_WRAPPING" ]; then
  SNAP=/snap/kde-frameworks-5-96-qt-5-15-5-core20-sdk/current
  ARCH=#{gnu_arch}-linux-gnu

  # Used by e.g. meinproc to locate XML assets at build-time
  export XDG_DATA_DIRS=$SNAP/usr/local/share:$SNAP/usr/share:$XDG_DATA_DIRS:/usr/share:/usr/local/share
  # Used by qtchooser to locate its configs.
  export XDG_CONFIG_DIRS=$SNAP/etc/xdg:/etc/xdg

  export LD_LIBRARY_PATH=$SNAP/usr/lib/$ARCH:$SNAP/usr/lib:$LD_LIBRARY_PATH
  export LD_LIBRARY_PATH=$SNAP/usr/lib/$ARCH/qt5/libs:$LD_LIBRARY_PATH:$LD_LIBRARY_PATH
  export PATH=$SNAP/bin:$SNAP/sbin:$SNAP/usr/bin:$KF5/usr/sbin:$PATH

  # Pulseaudio plugins [pulseaudi-common is a link-time requirement for symbols]
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$SNAP/usr/lib/$ARCH/pulseaudio

  # qtchooser hardcodes the global path, ignore it, it's always wrong!
  export QTCHOOSER_NO_GLOBAL_DIR=1
  export QT_SELECT=5
fi

exec $(dirname "$0")/snap-sdk-wrappers/#{basename} "$@"
      WRAPPER
      FileUtils.chmod(0o0755, exe, verbose: true)

      wrapped_exes << exe
    end
  end
end

# Set suitable qtchooser configs (the pertinent XDG_ variable is set
# by the wrapper),
qtchooser_config_dir = "#{root}/parts/kf5/install/etc/xdg/qtchooser/"
FileUtils.mkpath(qtchooser_config_dir)
File.write("#{qtchooser_config_dir}/default.conf", <<-CONF)
/snap/kde-frameworks-5-96-qt-5-15-5-core20-sdk/current/usr/lib/qt5/bin
/snap/kde-frameworks-5-96-qt-5-15-5-core20-sdk/current/usr/lib/#{gnu_arch}-linux-gnu
CONF
FileUtils.ln_s('default.conf', "#{qtchooser_config_dir}/qt5.conf", force: true)
FileUtils.ln_s('default.conf', "#{qtchooser_config_dir}/5.conf", force: true)
FileUtils.mkpath('/etc/xdg/qtchooser/', verbose: true)
File.write("/etc/xdg/qtchooser/default.conf", <<-CONF)
/usr/lib/qt5/bin
/usr/lib/#{gnu_arch}-linux-gnu
CONF
FileUtils.ln_s('default.conf', "/etc/xdg/qtchooser/qt5.conf", force: true)
FileUtils.ln_s('default.conf', "/etc/xdg/qtchooser/5.conf", force: true)
