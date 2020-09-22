#!/usr/bin/ruby

# Android has a huge and monolithic build system that does not allow to build
# components separately.
# This script tries to mimic Android build system for a small subset of source.

def expand(dir, files)
  files.map { |f| File.join(dir, f) }
end

# Compiles sources to *.o files.
# Returns array of output *.o filenames
def compile(sources, cflags, params = {})
  outputs = []
  for s in sources
    ext = File.extname(s)

    case ext
    when ".c"
      cc = "cc"
    when ".cpp", ".cc"
      cc = "cxx"
    else
      raise "Unknown extension #{ext}"
    end

    output = s + ".o"
    outputs << output
    order_deps = if params[:order_deps]
        " || " + params[:order_deps].join(" ")
      else
        ""
      end

    # TODO: try to build the tools with LLVM libc: -stdlib=libc++
    puts "build #{output}: #{cc} #{s}#{order_deps}\n    cflags = #{cflags}"
  end

  return outputs
end

# Generate proto and compile it
def protoc(source)
  basename = File.join(File.dirname(source), File.basename(source, ".proto"))
  cfile = basename + ".pb.cc"
  hfile = basename + ".pb.h"
  ofile = cfile + ".o"
  puts "build #{cfile} #{hfile}: protoc #{source}"
  puts "build #{ofile}: cxx #{cfile}\n    cflags = -I."

  return hfile, cfile, ofile
end

# Generate cpp and compile it
def yacc(source, cflags = "")
  basename = File.join(File.dirname(source), File.basename(source, ".yy"))
  cfile = basename + ".cpp"
  hfile = basename + ".h"
  ofile = cfile + ".o"
  puts "build #{cfile}: yacc #{source}\n    header = #{hfile}"
  puts "build #{ofile}: cxx #{cfile}\n    cflags = -I. #{cflags}"

  return hfile, cfile, ofile
end

# Generate cpp and compile it
def lex(source, cflags = "")
  basename = File.join(File.dirname(source), File.basename(source, ".ll"))
  cfile = basename + ".cpp"
  ofile = cfile + ".o"
  puts "build #{cfile}: lex #{source}"
  puts "build #{ofile}: cxx #{cfile}\n    cflags = -I. #{cflags}"

  return cfile, ofile
end

# dir - directory where ninja file is located
# lib - static library path relative to dir
def subninja(dir, lib)
  puts "subninja #{dir}build.ninja"
  return lib.each { |l| dir + l }
end

def lib(output, objects, ldflags)
  puts "build #{output}: lib #{objects.join(" ")}\n    ldflags = #{ldflags}"
end

# Links object files
def link(output, objects, ldflags)
  # TODO: try to build the tools with LLVM libc: -stdlib=libc++
  puts "build #{output}: link #{objects.join(" ")}\n    ldflags = #{ldflags}"
end

def genheader(input, variable, output)
  puts "build #{output}: genheader #{input}\n    var = #{variable}"
end

puts "# This set of commands generated by generate_build.rb script\n\n"
puts "CC = @CC@"
puts "CXX = @CXX@\n\n"
puts "CFLAGS = @CFLAGS@"
puts "CPPFLAGS = @CPPFLAGS@"
puts "CXXFLAGS = @CXXFLAGS@"
puts "LDFLAGS = @LDFLAGS@"
puts "PLATFORM_TOOLS_VERSION = @PV@\n\n"

puts "" "
rule cc
  command = $CC -std=gnu11 $CFLAGS $CPPFLAGS $cflags -c $in -o $out

rule cxx
  command = $CXX -std=gnu++2a $CXXFLAGS $CPPFLAGS $cflags -c $in -o $out

rule lib
  command = $CXX -shared -Wl,-soname,$out $ldflags $LDFLAGS $in -o $out

rule link
  command = $CXX $ldflags $LDFLAGS $in -o $out

rule protoc
  command = protoc --cpp_out=. $in

rule lex
  command = lex -o $out $in

rule yacc
  command = yacc --defines=$header -o $out $in

rule genheader
  command = (echo 'unsigned char $var[] = {' && xxd -i <$in && echo '};') > $out


" ""

basefiles = %w(
  chrono_utils.cpp
  file.cpp
  logging.cpp
  parsenetaddress.cpp
  quick_exit.cpp
  stringprintf.cpp
  strings.cpp
  test_utils.cpp
)
libbase = compile(expand("system/core/base", basefiles), "-fPIC -DADB_HOST=1 -Isystem/core/base/include -Isystem/core/include")
lib("libbase.so", libbase, "")

logfiles = %w(
  config_read.c
  config_write.c
  fake_log_device.c
  fake_writer.c
  local_logger.c
  log_event_list.c
  log_event_write.c
  logger_lock.c
  logger_name.c
  logger_write.c
  logprint.c
  stderr_write.c
)
liblog = compile(expand("system/core/liblog", logfiles), "-fPIC -DLIBLOG_LOG_TAG=1006 -D_XOPEN_SOURCE=700 -DFAKE_LOG_DEVICE=1 -Isystem/core/include")
lib("liblog.so", liblog, "")

cutilsfiles = %w(
  android_get_control_file.cpp
  canned_fs_config.cpp
  fs_config.cpp
  load_file.cpp
  socket_inaddr_any_server_unix.cpp
  socket_local_client_unix.cpp
  socket_local_server_unix.cpp
  socket_network_client_unix.cpp
  sockets.cpp
  sockets_unix.cpp
  threads.cpp
  trace-host.cpp
)
libcutils = compile(expand("system/core/libcutils", cutilsfiles), "-fPIC -DPROP_NAME_MAX=32 -D_GNU_SOURCE -Isystem/core/libcutils/include -Isystem/core/include")
lib("libcutils.so", libcutils, "")

zipfiles = %w(
  zip_archive.cc
  zip_archive_stream_entry.cc
  zip_writer.cc
)
## we use -std=c++17 as this lib currently does not compile with c++20 standard due to
## https://stackoverflow.com/questions/37618213/when-is-a-private-constructor-not-a-private-constructor/57430419#57430419
libzip = compile(expand("system/core/libziparchive", zipfiles), "-fPIC -std=c++17 -Isystem/core/base/include -Isystem/core/include -Isystem/core/libziparchive/include -Isystem/core/libcutils/include")
lib("libziparchive.so", libzip, "")

utilfiles = %w(
  FileMap.cpp
  JenkinsHash.cpp
  RefBase.cpp
  SharedBuffer.cpp
  Static.cpp
  String16.cpp
  String8.cpp
  StrongPointer.cpp
  Threads.cpp
  VectorImpl.cpp
  Unicode.cpp
)
libutil = compile(expand("system/core/libutils", utilfiles), "-fPIC -Isystem/core/include -Isystem/core/base/include")
lib("libutils.so", libutil, "")
