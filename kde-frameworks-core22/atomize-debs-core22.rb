# New frameworks content pack on core22. Build 11

require 'fileutils'
require 'json'
require 'tmpdir'
require 'yaml'

class Source
  attr_reader :upstream_name
  attr_reader :upstream_version

  def initialize(upstream_name)
    @upstream_name = upstream_name
  end

  def all_qml_depends
    @all_qml_depends ||= controls.collect do |control|
      control.binaries.collect do |binary|
        next nil unless runtime_binaries.include?(binary['package'])
        deps = binary.fetch('depends', []) + binary.fetch('recommends', [])
        deps.collect do |dep|
          dep = [dep[0]] if dep.size > 1
          next nil unless dep[0].name.start_with?('qml-module')
          dep = dep.each { |y| y.architectures = nil; y.version = nil; y.operator = nil }
          # puts "---> #{dep} ---> #{dep[0].substvar?}"
          dep = dep.reject(&:substvar?)
          dep.collect(&:to_s)
        end.compact
      end.flatten
    end.flatten
  end

  def dev_binaries
    dev_only(all_packages)
  end

  def runtime_binaries
    runtime_only(all_packages)
  end

  def all_build_depends
    @all_build_depends ||= controls.collect do |control|
      bdeps = control.source.fetch('build-depends', []) +
              control.source.fetch('build-depends-indep', [])
      bdeps.collect do |x|
        # TODO: this makes a bunch of assumptions as we have no proper
        #   resolver for dependencies. in alternates the first always wins
        #   architecture restrictions are entirely ignored
        x = [x[0]] if x.size > 1
        x = x.each { |y| y.architectures = nil; y.version = nil; y.operator = nil }
        x.collect(&:to_s)
      end.compact
    end.flatten
  end

  private

  def read_upstream_version(dir)
    version = `dpkg-parsechangelog -S version -l #{dir}/debian/changelog`.strip
    unless $?.success?
      warn 'Got error during dpkg-parsechangelog!'
      warn version
      return nil
    end
    version = version.split(':', 2)[-1] # ditch epoch
    version.split('-', 2)[0] # ditch rev
  end

  def parse_control(src)
    p src
    system("apt-get --download-only source #{src}") || raise
    FileUtils.mkpath('source/')
    files = 'debian/control debian/changelog'
    system("tar -xvf *debian.tar.* -C source #{files}") || raise
    @upstream_version = read_upstream_version('source')
    require_relative 'debian/control'
    control = Debian::Control.new('source')
    control.parse!
    control
  end

  def controls
    @controls ||= sources.collect do |src|
      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) do
          parse_control(src)
        end
      end
    end
  end


  def all_packages
    @all_packages ||= controls.collect do |control|
      control.binaries.collect { |x| x.fetch('package') }
    end.flatten
  end

  def dev_only(packages)
    packages.select do |pkg|
      pkg.include?('-dev') && !(pkg == 'qt5-qmake-arm-linux-gnueabihf')
    end
  end

  def runtime_only(packages)
    packages.delete_if do |pkg|
      pkg.include?('-dev') || pkg.include?('-doc') || pkg.include?('-dbg') ||
        pkg.include?('-examples') || pkg == 'qt5-qmake-arm-linux-gnueabihf'
    end
  end

  MAP = {
    'qt5' => %w[qtbase-opensource-src
                qtscript-opensource-src
                qtdeclarative-opensource-src
                qttools-opensource-src
                qtsvg-opensource-src
                qtx11extras-opensource-src],
    'kwallet' => %w[kwallet-kf5],
    'kdnssd' => %w[kdnssd-kf5],
    'baloo' => %w[baloo-kf5],
    'kdoctools' => %w[kdoctools5],
    'kfilemetadata' => %w[kfilemetadata-kf5],
    'attica' => %w[attica-kf5],
    'kactivities' => %w[kactivities-kf5]
  }.freeze

  def sources
    MAP.fetch(@upstream_name, [@upstream_name])
  end
end

class SnapcraftConfig
  module AttrRecorder
    def attr_accessor(*args)
      record_readable(*args)
      super
    end

    def attr_reader(*args)
      record_readable(*args)
      super
    end

    def record_readable(*args)
      @readable_attrs ||= []
      @readable_attrs += args
    end

    def readable_attrs
      @readable_attrs
    end
  end

  module YamlAttributer
    def encode_with(c)
      c.tag = nil # Unset the tag to prevent clutter
      self.class.readable_attrs.each do |readable_attrs|
        next unless data = method(readable_attrs).call
        c[readable_attrs.to_s.tr('_', '-')] = data
      end
      super(c) if defined?(super)
    end
  end

  class Part
    extend AttrRecorder
    prepend YamlAttributer

    # Array<String>
    attr_accessor :after
    # String
    attr_accessor :plugin
    # String
    attr_accessor :build_attributes
    # Array<String>
    attr_accessor :build_packages
    # Array<String>
    attr_accessor :stage_packages
    # Array<String>
    attr_accessor :prime
    # Array<String>
    attr_accessor :stage
    # Hash<String, String>
    attr_accessor :organize
    # String script
    attr_accessor :override_build
    # String script
    attr_accessor :build
    # String script
    attr_accessor :install

    # This cannot be read again! The reason is that when serializing into
    # YAML we need something to iterate on, that's readable attributes. Since
    # these are not readable they'll not get serialzed by default.
    # NB: when adding a new attribute here, you need to manually serialize
    #   it in #encode_with!
    attr_writer :source
    attr_writer :source_branch
    attr_writer :cmake_parameters

    def initialize
      @after = []
      @plugin = 'nil'
      @build_attributes = ['enable-patchelf']
      @build_packages = []
      @stage_packages = []
      @stage = %w[
        -usr/share/doc/*
        -usr/share/man/*
        -usr/share/icons/breeze/*.rcc
        -usr/share/wallpapers/*
        -usr/share/fonts/*
      ]
      @prime = %w[
        -usr/lib/*/cmake/*
        -usr/lib/*/qt5/bin/moc
        -usr/lib/*/qt5/bin/qmake
        -usr/lib/*/qt5/bin/rcc
        -usr/lib/*/qt5/bin/*cpp*
        -usr/lib/qt5/bin/assistant
        -usr/lib/qt5/bin/designer
        -usr/lib/qt5/bin/lconvert
        -usr/lib/qt5/bin/linguist
        -usr/lib/qt5/bin/lupdate
        -usr/lib/qt5/bin/lrelease
        -usr/lib/qt5/bin/moc
        -usr/lib/qt5/bin/pixeltool
        -usr/lib/qt5/bin/qcollectiongenerator
        -usr/lib/qt5/bin/qdbuscpp2xml
        -usr/lib/qt5/bin/qdbusxml2cpp
        -usr/lib/qt5/bin/qdoc
        -usr/lib/qt5/bin/qhelpconverter
        -usr/lib/qt5/bin/qlalr
        -usr/lib/qt5/bin/qmake
        -usr/lib/qt5/bin/rcc
        -usr/lib/qt5/bin/syncqt.pl
        -usr/lib/vlc/plugins/gui/libqt4_plugin.so
        -usr/include/*
        -usr/share/ECM/*
        -usr/share/xml/docbook/*
        -usr/share/doc/*
        -usr/share/locale/*/LC_MESSAGES/vlc.mo
        -usr/share/man/*
        -usr/share/icons/breeze/*.rcc
        -usr/share/icons/breeze-dark/*.rcc
        -usr/share/wallpapers/*
        -usr/share/fonts/*
        -usr/share/pkgconfig
        -usr/lib/*/pkgconfig
        -usr/share/QtCurve
        -usr/share/kde4
        -usr/share/bug
        -usr/share/debhelper
        -usr/share/lintian
        -usr/share/menu
        -usr/bin/*vlc
        -usr/bin/dh_*
        -usr/lib/*/*.a
        -usr/lib/*/*.pri
        -usr/share/kf5/kdoctools/*
        -usr/bin/make
      ]
      # @organize = {
      #   'etc/*' => 'slash/etc/',
      #   'usr/*' => 'slash/usr/'
      # }
    end

    def encode_with(c)
      if @plugin != 'nil'
        c['cmake-parameters'] = @cmake_parameters if @cmake_parameters
        c['source'] = @source
        # Slap in all source_* attributes for good measure.
        instance_variables.each do |v|
          name = v.to_s.tr('@', '').tr('_', '-')
          next unless v.to_s.start_with?('@source_')
          c[name] = instance_variable_get(v)
        end
      end
      super if defined?(super)
    end
  end

  class Slot
    extend AttrRecorder
    prepend YamlAttributer

    attr_accessor :content
    attr_accessor :interface
    attr_accessor :read
  end

  class PackageRepository
    extend AttrRecorder
    prepend YamlAttributer

    attr_accessor :type
    attr_accessor :components
    attr_accessor :suites
    attr_accessor :key_id
    attr_accessor :url
    attr_accessor :key_server
  end

  extend AttrRecorder
  prepend YamlAttributer

  attr_accessor :name
  attr_accessor :version
  attr_accessor :summary
  attr_accessor :description
  attr_accessor :confinement
  attr_accessor :grade
  attr_accessor :slots
  attr_accessor :package_repositories
  attr_accessor :parts
  attr_accessor :base
  attr_accessor :compression

  def initialize
    @parts = {}
    @slots = {}
    @package_repositories = []
  end
end

config = SnapcraftConfig.new
config.name = 'kf5-5-105-qt-5-15-9-core22'
config.version = 'unknown'
config.summary = 'KDE Frameworks 5'
config.description = 'KDE Frameworks are addons and useful extensions to Qt'
config.confinement = 'strict'
config.grade = 'stable'
config.base = 'core22'
config.compression = 'lzo'

slot = SnapcraftConfig::Slot.new
slot.content = 'kf5-5-105-qt-5-15-9-core22-all'
slot.interface = 'content'
slot.read = %w[.]
config.slots['kf5-5-105-qt-5-15-9-core22-slot'] = slot

package_repo = SnapcraftConfig::PackageRepository.new
package_repo.type = 'apt'
package_repo.components = %w[main]
package_repo.suites = %w[jammy]
package_repo.key_id = '444DABCF3667D0283F894EDDE6D4736255751E5D'
package_repo.url = 'http://origin.archive.neon.kde.org/release'
package_repo.key_server = 'keyserver.ubuntu.com'
config.package_repositories.push(package_repo)

# These are only old versions! The new version is created later after we know
# the current versions of the content.
content_versions = []
if File.exist?('versions.json')
  content_versions = JSON.parse(File.read('versions.json')).uniq
end
content_versions.each do |content_version|
  slot = SnapcraftConfig::Slot.new
  slot.content = content_version
  slot.interface = 'content'
  slot.read = %w[.]
  config.slots[content_version] = slot
end

# This list is generated by resolving and sorting the dep tree from
# kde-build-metadata. Commented out bits we don't presently want to build.
parts = %w(extra-cmake-modules kcoreaddons) + # kdesupport/polkit-qt-1
        %w(kauth kconfig kwidgetsaddons kcompletion
           kwindowsystem kcrash karchive ki18n kfilemetadata
           kjobwidgets kpty kunitconversion kcodecs) + # kdesupport/phonon/phonon
        %w(knotifications kpackage kguiaddons kconfigwidgets kitemviews
           kiconthemes attica kdbusaddons kservice kglobalaccel sonnet
           ktextwidgets breeze-icons kxmlgui kbookmarks solid kwallet kio
           kdeclarative kcmutils kplotting kparts kdewebkit
           kemoticons knewstuff kinit knotifyconfig kded
           kdesu ktexteditor kactivities kactivities-stats
           kdnssd kidletime kitemmodels threadweaver
           plasma-framework kxmlrpcclient kpeople frameworkintegration
           kdoctools
           kdesignerplugin
           ksyntax-highlighting
           krunner kwayland baloo breeze
           libkdegames
           kross kdelibs4support)
           # plasma-integration) # extra integration pulls in breeze pulls in kde4/qt4
parts += %w[qtwebkit qtbase qtdeclarative qtgraphicaleffects qtlocation
            qtmultimedia qtquickcontrols qtquickcontrols2 qtscript qtsensors
            qtserialport qtsvg qttools qttranslations qtvirtualkeyboard
            qtwayland qtwebchannel qtwebengine qtwebsockets qtwebview qtx11extras
            qtxmlpatterns qtconnectivity].collect { |x| x + '-opensource-src' }
#
# oxygen-icons5 only one icon set
# Not Runtime Relevant! FIXME: need to seperate these out to only end up in -dev but not content!
#   extra-cmake-modules
#   kdesignerplugin
#   kdoctools
# No Porting Aids!
#   kdelibs4support
#   khtml
#   kjs
#   kjsembed
#   kmediaplayer
#   kross

# padding
parts = [nil] + parts
# parts += [nil]

# Stuff which is (transitively) pulled into the runtime but not in the devs.
# This usually shows up in production as libfoo.so.x.y being in the runtime but
# the headers not being in the sdk. This causes trouble as there is a divide
# between binary-in runtime and the dev headers staged by an app that wants to
# use these libraries. So, it's generally smart to pack them in the sdk even
# though they are not strictly frameworks.
# Notable exception: ssl (multiple versions available)
devs = %w[libxml2-dev libxslt-dev liblcms2-dev libpng-dev libexiv2-dev
          libjpeg-dev]
# make sure we have gettext available for l10n use
devs += %w[gettext]
# mesa-utils-extra - es2_info useful to debug GL problems.
runs = %w[mesa-utils-extra freeglut3-dev libglib2.0-0]
# GStreamer plugins
runs += %w[gstreamer1.0-x gstreamer1.0-plugins-base
           gstreamer1.0-pulseaudio gstreamer1.0-plugins-good]
# For on-demand locale generation we need the raw data to generate locales from.
runs += %w[locales libc-bin]
runs += %w[gettext libdrm-dev]
# VA-API drivers for HW-accelerated video decoding
runs += %w[mesa-va-drivers] 
runs << { "on amd64" => %w[i965-va-driver intel-media-va-driver] }

kf5_version = nil
qt5_version = nil

parts.each_cons(2) do |first_name, second_name|
  # puts "#{second_name} AFTER #{first_name}"
  next unless second_name # first item is nil
  source = Source.new(second_name)
  devs += source.dev_binaries
  runs += source.runtime_binaries
  if source.upstream_name == 'extra-cmake-modules' && config.version
    kf5_version = source.upstream_version
    config.version = '5.105'
  end
  if source.upstream_name == 'qtbase-opensource-src'
    qt5_version = '5.15.9'
  end
end

# Construct a new interface name with up to date versions.
# This is the only way we can version a content snap.
#kf5_version = 'kf5-' + kf5_version.split('.')[0..1].join('-')
#qt5_version = 'qt-' + qt5_version.split('.')[0..0].join('-')
kf5_version = 'kf5-5-105'
qt5_version = 'qt-5-15-9'
platform_version = 'core22'

latest_version = [kf5_version, qt5_version, platform_version].join('-')
# Dump the latest interface. The application builds will pick this up and
# set it as their content provider, this way we should be able to prevent
# Qt version mismatches.
File.write('content.json',
           JSON.generate(latest_version))
unless config.slots.include?(latest_version)
  slot = SnapcraftConfig::Slot.new
  slot.content = latest_version
  slot.interface = 'content'
  slot.read = %w[.]
  config.slots[latest_version] = slot

  content_versions << latest_version
  File.write('versions.json', JSON.generate(content_versions.uniq))
end

# Do not pull in the GTK stack.
runs.delete('qt5-gtk-platformtheme')
devs.delete('qt5-gtk-platformtheme')

mesapart = SnapcraftConfig::Part.new
mesapart.stage_packages = ['libgl1-mesa-dri', 'libglx-mesa0']
mesapart.stage = nil
mesapart.build_attributes = ['no-patchelf']
mesapart.prime = %w[
        -lib/udev
        -usr/doc
        -usr/doc-base
        -usr/share/applications
        -usr/share/apport
        -usr/share/bug
        -usr/share/doc
        -usr/share/doc-base
        -usr/share/icons
        -usr/share/libdrm
        -usr/share/libwacom
        -usr/share/lintian
        -usr/share/man
        -usr/share/pkgconfig
]
config.parts['mesa'] = mesapart

part = SnapcraftConfig::Part.new
part.stage_packages = runs.flatten
part.stage = (part.stage + %w[
  -usr/bin/checkXML5
  -usr/bin/kpackagetool5
  -usr/bin/meinproc5
  -usr/lib/qt5/bin/qdoc
  -usr/lib/qt5/bin/qhelpgenerator
  -usr/lib/qt5/bin/qtattributionsscanner
  -usr/lib/*/qt5/bin/qmake
]).uniq
config.parts['kf5'] = part

dev = SnapcraftConfig::Part.new
dev.stage_packages = devs.flatten
dev.stage = (dev.stage + %w[
  -usr/share/emoticons
  -usr/share/icons/*
  -usr/share/locale/*/LC_*/*
  -usr/share/qt5/translations/*
  -usr/lib/*/dri/*
  -usr/share/qtchooser/qt5-*.conf
  -usr/lib/*/libexec/kf5/kconf_update
]).uniq
dev.prime = ['-*']
dev.after = %w(kf5)
config.parts['kf5-dev'] = dev

integration = SnapcraftConfig::Part.new
integration.after = %w(kf5-dev)
integration.build_packages = %w(
               extra-cmake-modules
               gettext
               kio-dev
               kwayland-dev
               libkf5config-dev
               libkf5configwidgets-dev
               libkf5doctools-dev
               libkf5i18n-dev
               libkf5iconthemes-dev
               libkf5notifications-dev
               libkf5widgetsaddons-dev
               libqt5x11extras5-dev
               libxcursor-dev
               qtbase5-dev
               qtbase5-private-dev
               qtwayland5-dev-tools
               libqt5waylandclient5-dev
               libwayland-dev
               breeze-dev
               plasma-wayland-protocols
)
integration.cmake_parameters = %w(
  -DCMAKE_INSTALL_PREFIX=/usr
  -DCMAKE_BUILD_TYPE=Release
  -DENABLE_TESTING=OFF
  -DBUILD_TESTING=OFF
  -DKDE_SKIP_TEST_SETTINGS=ON
)
integration.stage_packages = %w(libxcursor1)
integration.plugin = 'cmake'
integration.source = 'https://invent.kde.org/plasma/plasma-integration.git'
integration.source_branch = 'Plasma/5.27'
config.parts['plasma-integration'] = integration

FileUtils.mkpath('runtime')
puts File.write('runtime/snapcraft.yaml', YAML.dump(config, indentation: 4))
puts File.write('runtime.snapcraft.yaml', YAML.dump(config, indentation: 4))
puts File.write('stage-content.json', JSON.generate(runs))
puts File.write('stage-dev.json', JSON.generate(runs + devs))

### sdk snap

config.name = 'kf5-5-105-qt-5-15-9-core22-sdk'
# We mustn't define the slots in the SDK, it'd confuse snapd on what to
# autoconnect when both snaps are installed.
config.slots.clear

sdk_wrapper = SnapcraftConfig::Part.new
sdk_wrapper.plugin = 'dump'
sdk_wrapper.source = 'sdk-wrapper/'
sdk_wrapper.prime = ['-*']
config.parts['sdk-wrapper'] = sdk_wrapper

config.parts['kf5'].prime = ['-usr/lib/*/qt5/bin/qmake']
# wrap the exectuable cmake targets to have a suitable LD_LIBRARY_PATH
config.parts['kf5'].build_packages = ['ruby']
config.parts['kf5'].override_build = "pwd; $SNAPCRAFT_STAGE/sdk_wrapper.sh\n$SNAPCRAFT_STAGE/sdk_wrapper.rb kf5\nsnapcraftctl build"
config.parts['kf5'].after = ['sdk-wrapper']

config.parts['kf5-dev'].prime = nil
# wrap the exectuable cmake targets to have a suitable LD_LIBRARY_PATH
config.parts['kf5-dev'].override_build = "pwd; $SNAPCRAFT_STAGE/sdk_wrapper.rb kf5-dev\nsnapcraftctl build"

config.parts['plasma-integration'].prime = nil
# wrap the exectuable cmake targets to have a suitable LD_LIBRARY_PATH
#config.parts['plasma-integration'].override_build = "pwd; /sdk_wrapper.rb plasma-integration\nsnapcraftctl build"

FileUtils.mkpath('sdk')
puts File.write('sdk/snapcraft.yaml', YAML.dump(config, indentation: 4))
puts File.write('sdk.snapcraft.yaml', YAML.dump(config, indentation: 4))
