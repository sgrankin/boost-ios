## What?

A build script to compile [Boost](http://www.boost.org)
([1.51.0](http://www.boost.org/users/history/version_1_51_0.html) or so) for iOS.

## Why?
Because your iPhone doesn't get enough c++.

## How?

### The blue pill
Prerequisites:

- [Subversion](http://subversion.tigris.org)

Sync 'n build:

```sh
$ ./boost-jam.rb
```

(For more options, such as setting which SDK or libraries you want), see --help.

You should now have a framework in `./boost.framework`.  Drag'n'drop to Xcode and get compiling!

### The red pill

Prerequisites:

- [Git](http://git-scm.com)
- [CMake](http://www.cmake.org)
- [Ninja](http://martine.github.com/ninja/)

Clone this repo:

```sh
$ git clone http://github.com/sagran/boost-ios.git
```

Clone other repos:

```sh
$ git submodule init
$ git submodule update
```

Now would be a good time to check `./boost-zero` and see if you want to check out a different version.

Configure the script. You want to make sure the boost version matches the source, and the sdk version matches your sdk.

```ruby
$ editor boost-cmake.rb
BOOST_VERSION=1_51_0
IPHONEOS_SDK_VERSION='6.0'
IPHONEOS_DEPLOYMENT_TARGET='5.1'
DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'
```

Fix the boost sources:

```sh
$ rm -r boost-zero/boost/graph_parallel
$ rm -r boost-zero/boost/mpi
$ rm -r boost-zero/boost/python
$ ruby -i~ -p -e '$_ = nil if /boost\/(graph_parallel|mpi|python)/ === $_' boost-zero/CMakeLists.txt
```

```diff
+++ boost-zero/boost/context/CMakeLists.txt
-    src/stack_utils_posix.cpp
```

```diff
+++ boost-zero/boost/core/CMakeLists.txt
-set(Boost_VERSION_MINOR 50)
+set(Boost_VERSION_MINOR 51)

-string(REPLACE "." "_" BOOST_LIB_VERSION "${Boost_VERSION}")
+set(BOOST_LIB_VERSION "${Boost_VERSION_MAJOR}_${Boost_VERSION_MINOR}_${Boost_VERSION_PATCH}")
```

```diff
+++ boost-zero/boost/inspect/CMakeLists.txt
   unnamed_namespace_check.cpp
+  deprecated_macro_check.cpp
```

Go!
```sh
$ ./boost-cmake.rb
```

You should now have a framework in `./boost.framework`.  Drag'n'drop to Xcode and get compiling!

## References, inspirations, etc.

- http://code.google.com/p/ios-cmake/
- http://gitorious.org/boostoniphone/boostoniphone
- http://www.cmake.org/Wiki/CMake_Cross_Compiling
- https://gitorious.org/~galbraithjoseph/boostoniphone/galbraithjosephs-boostoniphone
