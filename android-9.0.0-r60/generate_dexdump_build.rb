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


libdexfiles = %w(
  CmdUtils.cpp
  DexCatch.cpp
  DexClass.cpp
  DexDataMap.cpp
  DexDebugInfo.cpp
  DexFile.cpp
  DexInlines.cpp
  DexOptData.cpp
  DexOpcodes.cpp
  DexProto.cpp
  DexSwapVerify.cpp
  DexUtf.cpp
  InstrUtils.cpp
  Leb128.cpp
  OptInvocation.cpp
  sha1.cpp
  SysUtil.cpp
)
libdex = compile(expand("dalvik/libdex", libdexfiles), "-Idalvik")
dexdumpfiles = %w(
  DexDump.cpp
)
dexdump = compile(expand("dalvik/dexdump", dexdumpfiles), "-Idalvik")
link("dexdump", libdex + dexdump, "-lz -lsafe-iop -lnativehelper -lbase -lutils -llog -lziparchive")
