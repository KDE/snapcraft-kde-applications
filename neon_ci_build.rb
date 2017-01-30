#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2017 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

SOURCES = [
  'deb http://archive.neon.kde.org/user xenial main',
  'deb http://archive.neon.kde.org/release xenial main'
].freeze
ARCHIVE_KEY = '444D ABCF 3667 D028 3F89  4EDD E6D4 7362 5575 1E5D'.freeze

builddir = File.read('builddir').strip

File.open('/etc/apt/sources.list.d/neon.list', 'w') do |f|
  SOURCES.each { |line| f.puts(line) }
end
system('apt-key', 'adv',
       '--keyserver', 'keyserver.ubuntu.com',
       '--recv', ARCHIVE_KEY) || raise
system('apt', 'update') # ignore errors here. snapcraft will handle it.

system('snapcraft', chdir: builddir) || raise
