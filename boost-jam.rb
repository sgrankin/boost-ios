#!/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/bin/ruby -wKU
require 'optparse'
require 'ostruct'
require 'pathname'
require 'rake'
require 'shellwords'

$opts = OpenStruct.new
OptionParser.new do |op|
  op.on('--boost-version version',    'Version of boost to sync and build (default is latest SVN)')     {|val| $opts.boost_version = val}
  op.on('--sdk version',              'Version of IOS SDK to build against (default 6.0)')              {|val| $opts.sdk_version = val}
  op.on('--target version',           'Minimum IOS SDK version to support (default 5.0)')               {|val| $opts.min_version = val}
  op.on('--developer-dir dir',        'Developer directory (default from xcode-select)')                {|val| $opts.developer_dir = val}
  op.on('--libraries lib1,lib2,...',  'Libraries to build (default all but graph_parallel,mpi,python)') {|val| $opts.libraries = val.split(',')}
end.parse!

# last SVN release if version unspecified
BOOST_SVN = 'http://svn.boost.org/svn/boost/tags/release'
boost_branch = $opts.boost_version ? "Boost_#{$opts.boost_version}" : `svn ls #{BOOST_SVN}`.lines.sort.last.chomp.gsub(/\/$/,'')
boost_version = boost_branch.split('_', 1)[1]
boost_svn_branch = "#{BOOST_SVN}/#{boost_branch}"

SRC = Pathname.new 'src'

mkdir_p SRC
if File.exist?(SRC + '.svn')
  unless boost_svn_branch == `svn info #{SRC}`.lines.grep(/^URL/).first.chomp.split[1]
    sh %{svn sw #{boost_svn_branch} #{SRC}}
  end
else
  sh %{svn co #{boost_svn_branch} #{SRC}}
end

SDK_VERSION = $opts.sdk_version || '6.0'
MIN_VERSION = $opts.min_version || '5.0'

DEVELOPER_DIR = $opts.developer_dir || `xcode-select -print-path`.chomp || '/Applications/Xcode.app/Contents/Developer'

CXX = `xcrun -find clang++`.chomp
CXX_FLAGS = %W{-DBOOST_AC_USE_PTHREADS
               -DBOOST_SP_USE_PTHREADS
               -Wno-unused-function
               -Wno-unused-parameter
               -Wno-unused-variable
               -std=gnu++11 -stdlib=libc++
               -g
}.join(' ')

open(SRC + 'tools/build/v2/user-config.jam', 'w') do |io|
  io.print <<-EOF
  using darwin : #{SDK_VERSION}~iphone
   : #{CXX} -arch armv7 -arch armv7s -fvisibility=hidden -fvisibility-inlines-hidden #{CXX_FLAGS}
   : <root>#{DEVELOPER_DIR}/Platforms/iPhoneOS.platform/Developer
   : <architecture>arm <target-os>iphone
   ;
using darwin : #{SDK_VERSION}~iphonesim
   : #{CXX} -arch i386 -fvisibility=hidden -fvisibility-inlines-hidden #{CXX_FLAGS}
   : <root>#{DEVELOPER_DIR}/Platforms/iPhoneSimulator.platform/Developer
   : <architecture>x86 <target-os>iphone
   ;
   EOF
end

system %{patch -N -p0 < boost-jam.patch}

# libs we don't like... since they don't seem to build
without_libraries = %w{graph_parallel mpi python locale}
with_libraries = ($opts.libraries || []) - without_libraries

without_libraries = without_libraries.join(',')
with_libraries = with_libraries.join(',')

cd SRC do
  if with_libraries.length > 0
    sh %W{./bootstrap.sh --with-toolset=darwin --with-libraries=#{with_libraries}}.shelljoin
  else
    sh %W{./bootstrap.sh --with-toolset=darwin --without-libraries=#{without_libraries}}.shelljoin
  end

  sh %W{./b2 --build-dir=../build --stagedir=../stage/iphone --prefix=../install
        variant=release
        link=static
        pch=off
        target-os=iphone
        macosx-version=iphone-#{SDK_VERSION}
        macosx-version-min=iphone-#{MIN_VERSION}
        architecture=arm
        define=_LITTLE_ENDIAN
        toolset=darwin
        stage install}.shelljoin

        sh %W{./b2 --build-dir=../build --stagedir=../stage/iphonesim
        variant=release
        link=static
        toolset=darwin
        target-os=iphone
        macosx-version=iphonesim-#{SDK_VERSION}
        macosx-version-min=iphonesim-#{MIN_VERSION}
        architecture=x86
        stage}.shelljoin
end

FRAMEWORK_NAME    = 'boost'
FRAMEWORK_VERSION = 'A'
FRAMEWORK_CURRENT_VERSION = boost_version

framework_bundle = Pathname.new("#{FRAMEWORK_NAME}.framework")

mkdir_p framework_bundle
mkdir_p framework_bundle + 'Versions'
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION + 'Resources'
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION + 'Headers'
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION + 'Documentation'

def link_once src, dst
  unless File.symlink?(dst) or File.file?(dst)
    ln_sf src, dst
  end
end
link_once FRAMEWORK_VERSION,                     framework_bundle + 'Versions' + 'Current'
link_once 'Versions/Current/Headers',            framework_bundle + 'Headers'
link_once 'Versions/Current/Resources',          framework_bundle + 'Resources'
link_once 'Versions/Current/Documentation',      framework_bundle + 'Documentation'
link_once "Versions/Current/#{FRAMEWORK_NAME}",  framework_bundle + FRAMEWORK_NAME

framework_install_name = framework_bundle + 'Versions' + FRAMEWORK_VERSION + FRAMEWORK_NAME

# create the mega library
LIBTOOL = `xcrun -find libtool`.chomp
sh %{#{LIBTOOL} -static -o #{framework_install_name.to_s.shellescape} #{Dir['stage/*//lib/*.a'].shelljoin}}

# copy includes from the first build
cp_r Dir['install/include/boost/*'], framework_bundle + 'Headers'

# create a plist
open(framework_bundle + 'Resources' + 'Info.plist', 'w') do |io|
  io.print <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleExecutable</key>
  <string>#{FRAMEWORK_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>org.boost</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleVersion</key>
  <string>#{FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
  EOF
end
