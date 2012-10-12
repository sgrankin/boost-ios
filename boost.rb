#!/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/bin/ruby -wKU
require 'pathname'
require 'rake'
require 'shellwords'

BOOST_VERSION=1_51_0

DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'
IPHONEOS_SDK_VERSION='6.0'
IPHONEOS_DEPLOYMENT_TARGET='5.1'

PLATFORMS = {
  'iPhoneOS' => {
    :sdk => 'iphoneos',
    :sdk_ver => IPHONEOS_SDK_VERSION,
    :arch => %w{armv7 armv7s},
    :target => 'iphoneos',
  },
  'iPhoneSimulator' => {
    :sdk => 'iphonesimulator',
    :sdk_ver => IPHONEOS_SDK_VERSION,
    :arch => %w{i386},
    :target => 'ios-simulator',
  },
}

def xcrun app
  return `xcrun -find #{app}`.chomp
end

CC = xcrun 'clang'
CXX = xcrun 'clang++'
LIBTOOL = xcrun 'libtool'

# boost configuration overrides:
# - BOOST_NO_CXX11_CONSTEXPR: xcode's stdlib is not standard compatible on constexpr labels
DEFINES = %w{
  BOOST_NO_CXX11_CONSTEXPR
}

PLATFORMS.each do |platform_name, platform|
  platform[:arch].each do |arch|
    platform_dir = "#{DEVELOPER_DIR}/Platforms/#{platform_name}.platform"
    platform_developer_dir = "#{platform_dir}/Developer"
    sdk_dir = "#{platform_dir}/Developer/SDKs/#{platform_name}#{platform[:sdk_ver]}.sdk"
    sdk_name = platform[:sdk] + platform[:sdk_ver]


    ENV['MACOSX_DEPLOYMENT_TARGET'] = IPHONEOS_SDK_VERSION

    build_dir = Pathname.new "build/#{platform[:sdk]}_#{arch}"
    mkdir_p build_dir
    chdir build_dir do
      open('toolchain.cmake', 'w') do |io|
        io.print <<-EOF
set (CMAKE_SYSTEM_NAME Darwin)
set (CMAKE_SYSTEM_VERSION #{IPHONEOS_SDK_VERSION})

set (CMAKE_C_COMPILER "#{CC}")
set (CMAKE_CXX_COMPILER "#{CXX}")

# force the compiler, since it won't pass any tests
include (CMakeForceCompiler)
CMAKE_FORCE_C_COMPILER (${CMAKE_C_COMPILER} GNU)
CMAKE_FORCE_CXX_COMPILER (${CMAKE_CXX_COMPILER} GNU)

set (CMAKE_C_HAS_ISYSROOT TRUE)
set (CMAKE_CXX_HAS_ISYSROOT TRUE)
set (CMAKE_C_OSX_DEPLOYMENT_TARGET_FLAG "-m#{platform[:target]}-version-min=")
set (CMAKE_C_OSX_DEPLOYMENT_TARGET "#{IPHONEOS_DEPLOYMENT_TARGET}")
set (CMAKE_CXX_OSX_DEPLOYMENT_TARGET_FLAG "-m#{platform[:target]}-version-min=")
set (CMAKE_CXX_OSX_DEPLOYMENT_TARGET "#{IPHONEOS_DEPLOYMENT_TARGET}")
set (CMAKE_XCODE_EFFECTIVE_PLATFORMS "-#{platform[:sdk]}")

# set (CMAKE_THREAD_PREFER_PTHREAD TRUE)

#set (CMAKE_C_OSX_COMPATIBILITY_VERSION_FLAG "-compatibility_version ")
#set (CMAKE_C_OSX_CURRENT_VERSION_FLAG "-current_version ")
#set (CMAKE_CXX_OSX_COMPATIBILITY_VERSION_FLAG "${CMAKE_C_OSX_COMPATIBILITY_VERSION_FLAG}")
#set (CMAKE_CXX_OSX_CURRENT_VERSION_FLAG "${CMAKE_C_OSX_CURRENT_VERSION_FLAG}")

# Use most-recent languages.
set (CMAKE_C_FLAGS_INIT "-g -std=gnu99" CACHE STRING "C_FLAGS")
set (CMAKE_CXX_FLAGS_INIT "-g -std=gnu++11 -stdlib=libc++ #{DEFINES.map{|d| "-D"+d}.join(' ')}" CACHE STRING "CXX_FLAGS")

set (CMAKE_IOS_DEVELOPER_ROOT "#{platform_developer_dir}" CACHE PATH "Location of iOS Platform")
set (CMAKE_IOS_SDK_ROOT "#{sdk_dir}" CACHE PATH "Location of iOS Platform")

set (CMAKE_OSX_SYSROOT ${CMAKE_IOS_SDK_ROOT} CACHE PATH "Sysroot used for iOS support")
set (CMAKE_OSX_ARCHITECTURES #{arch} CACHE string  "Build architecture for iOS")

# Set the find root to the iOS developer roots and to user defined paths
set (CMAKE_FIND_ROOT_PATH ${CMAKE_IOS_DEVELOPER_ROOT} ${CMAKE_IOS_SDK_ROOT} ${CMAKE_PREFIX_PATH} CACHE string  "iOS find search path root")

# default to searching for frameworks first
set (CMAKE_FIND_FRAMEWORK FIRST)

# set up the default search directories for frameworks
set (CMAKE_SYSTEM_FRAMEWORK_PATH
  ${CMAKE_IOS_SDK_ROOT}/System/Library/Frameworks
  ${CMAKE_IOS_SDK_ROOT}/System/Library/PrivateFrameworks
  ${CMAKE_IOS_SDK_ROOT}/Developer/Library/Frameworks
)

set (CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
set (CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set (CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
        EOF
      end

      cmake_flags = %w{
        -DBOOST_DISABLE_PCH=TRUE
        -DCMAKE_BUILD_TYPE=RELEASE
        -DCMAKE_INSTALL_COMPONENT=dev
        -DCMAKE_INSTALL_PREFIX=install
        -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake
        -DRYPPL_DISABLE_DOCS=TRUE
        -DRYPPL_DISABLE_EXAMPLES=TRUE
        -DRYPPL_DISABLE_TESTS=TRUE
      }.shelljoin

      unless File.exist? 'CMakeCache.txt'
        # run cmake twice, since that's what it wants...
        system %{cmake #{cmake_flags} -G Ninja ../../boost-zero/}
        sh     %{cmake #{cmake_flags} -G Ninja ../../boost-zero/}
      end

      # build the binaries
      sh %{ninja -k 0 all}

      # install binaries and headers into ./install
      #sh %{cmake #{cmake_flags} -P cmake_install.cmake}
      sh %{ninja install}

      # make sure our defines make it to the user
      open('install/include/boost/config/user.hpp', 'a') do |io|
        DEFINES.each do |d|
          io << "#define #{d}\n"
        end
      end
    end
  end
end

FRAMEWORK_NAME    = 'boost'
FRAMEWORK_VERSION = 'A'
FRAMEWORK_CURRENT_VERSION = BOOST_VERSION

framework_dir = Pathname.new 'build/framework'
framework_bundle = framework_dir + "#{FRAMEWORK_NAME}.framework"
mkdir_p framework_bundle
mkdir_p framework_bundle + 'Versions'
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION + 'Resources'
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION + 'Headers'
mkdir_p framework_bundle + 'Versions' + FRAMEWORK_VERSION + 'Documentation'

ln_sf FRAMEWORK_VERSION,                     framework_bundle + 'Versions' + 'Current'
ln_sf 'Versions/Current/Headers',            framework_bundle + 'Headers'
ln_sf 'Versions/Current/Resources',          framework_bundle + 'Resources'
ln_sf 'Versions/Current/Documentation',      framework_bundle + 'Documentation'
ln_sf "Versions/Current/#{FRAMEWORK_NAME}",  framework_bundle + FRAMEWORK_NAME

framework_install_name = framework_bundle + 'Versions' + FRAMEWORK_VERSION + FRAMEWORK_NAME

# create the mega library
sh %{#{LIBTOOL} -static -o #{framework_install_name.to_s.shellescape} #{Dir['build/*/install/lib/*.a'].shelljoin}}

# copy includes from the first build
cp_r Dir["#{Dir['build/*/install/include'].first}/boost/*"], framework_bundle + 'Headers'

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
