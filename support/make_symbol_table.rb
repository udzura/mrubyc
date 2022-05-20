#!/usr/bin/env ruby
#
# create built-in symbol table in ROM
#
#  Copyright (C) 2015-2022 Kyushu Institute of Technology.
#  Copyright (C) 2015-2022 Shimane IT Open-Innovation Center.
#
#  This file is distributed under BSD 3-Clause License.
#
# (usage)
# ruby make_symbol_table.rb [option]
#
#  -o output filename.
#  -i input symbol list filename.
#  -a Targets all .c files in the current directory.
#  -v verbose
#

require "optparse"
require_relative "common_sub"

APPEND_SYMBOL = [
  "",   # To make zero an error (reserved) value.

  "+", "-", "*", "/", "initialize", "collect", "map",
  "collect!", "map!", "delete_if", "each", "each_index",
  "each_with_index", "reject!", "reject", "sort!", "sort", "times",
  "loop", "each_byte", "each_char",
  "PI", "E",
  "RUBY_VERSION", "MRUBY_VERSION", "MRUBYC_VERSION", "RUBY_ENGINE",
]


##
# verbose print
#
def vp( s, level = 1 )
  STDERR.puts s  if $options[:v] >= level
end


##
# parse command line option
#
def get_options
  opt = OptionParser.new
  ret = {:i=>[], :v=>0}

  opt.on("-i input file") {|v| ret[:i] << v }
  opt.on("-o output file") {|v| ret[:o] = v }
  opt.on("-a", "targets all .c files") {|v| ret[:a] = v }
  opt.on("-v", "verbose mode") {|v| ret[:v] += 1 }
  opt.parse!(ARGV)
  return ret

rescue OptionParser::MissingArgument =>ex
  STDERR.puts ex.message
  return nil
end


##
# read *.c file and extract symbols.
#
def fetch_builtin_symbol( filename )
  ret = []
  vp("Process '#{filename}'")

  File.open( filename ) {|file|
    while src = get_method_table_source( file )
      param = parse_source_string( src )
      exit 1 if !param

      param[:classes].each {|cls|
        vp("Found class #{cls[:class]}, #{cls[:methods].to_a.size } methods.")
        ret << cls[:class]
        cls[:methods].to_a.each {|m| ret << m[:name] }
      }
    end
  }

  return ret
end


##
# write symbol table file.
#
def write_file( all_symbols )
  vp("Output file '#{$options[:o] || "STDOUT"}'")
  begin
    file = $options[:o] ? File.open( $options[:o], "w" ) : $stdout
  rescue Errno::ENOENT
    puts "File can't open. #{output_filename}"
    exit 1
  end

  file.puts "/* Auto generated by make_symbol_table.rb */"
  file.puts "#ifndef MRBC_SRC_AUTOGEN_BUILTIN_SYMBOL_H_"
  file.puts "#define MRBC_SRC_AUTOGEN_BUILTIN_SYMBOL_H_"
  file.puts

  file.puts "#if defined(MRBC_DEFINE_SYMBOL_TABLE)"
  file.puts "static const char *builtin_symbols[] = {"
  all_symbols.each_with_index {|s,i|
    s1 = %!  "#{s}",!
    s1 << "\t" * ([3 - s1.size / 8, 1].max)
    s1 << "// MRBC_SYMID_#{rename_for_symbol(s)} = #{i}"
    file.puts s1
  }
  file.puts "};"
  file.puts "#endif"
  file.puts

  file.puts "enum {"
  all_symbols.each_with_index {|s,i|
    file.puts "  MRBC_SYMID_#{rename_for_symbol(s)} = #{i},"
  }
  file.puts "};"

  file.puts
  file.puts "#define MRB_SYM(sym)  MRBC_SYMID_##sym"
  file.puts "#define MRBC_SYM(sym) MRBC_SYMID_##sym"
  file.puts "#endif"

  file.close  if $options[:o]
end


##
# main
#
$options = get_options()
exit if !$options

# read source file(s)
if !$options[:i].empty?
  source_files = $options[:i]
elsif $options[:a]
  source_files = Dir.glob("*.c")
else
  STDERR.puts "File not given."
  exit 1
end

all_symbols = []
source_files.each {|filename|
  all_symbols.concat( fetch_builtin_symbol( filename ) )
}
all_symbols.concat( APPEND_SYMBOL )
all_symbols.sort!
all_symbols.uniq!
vp("Total number of built-in symbols: #{all_symbols.size}")

if all_symbols.size > 256
  STDERR.puts "Symbol table size must be less than 256"
  exit 1
end

write_file( all_symbols )

vp("Done")
