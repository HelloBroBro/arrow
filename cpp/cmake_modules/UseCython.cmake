# Define a function to create Cython modules.
#
# For more information on the Cython project, see http://cython.org/.
# "Cython is a language that makes writing C extensions for the Python language
# as easy as Python itself."
#
# This file defines a CMake function to build a Cython Python module.
# To use it, first include this file.
#
#   include( UseCython )
#
# Then call cython_add_module to create a module.
#
#   cython_add_module( <target_name> <pyx_target_name> <output_files> <src1> <src2> ... <srcN> )
#
# Where <module_name> is the desired name of the target for the resulting Python module,
# <pyx_target_name> is the desired name of the target that runs the Cython compiler
# to generate the needed C or C++ files, <output_files> is a variable to hold the
# files generated by Cython, and <src1> <src2> ... are source files
# to be compiled into the module, e.g. *.pyx, *.c, *.cxx, etc.
# only one .pyx file may be present for each target
# (this is an inherent limitation of Cython).
#
# The sample paths set with the CMake include_directories() command will be used
# for include directories to search for *.pxd when running the Cython compiler.
#
# Cache variables that effect the behavior include:
#
#  CYTHON_ANNOTATE
#  CYTHON_NO_DOCSTRINGS
#  CYTHON_FLAGS
#
# Source file properties that effect the build process are
#
#  CYTHON_IS_CXX
#  CYTHON_IS_PUBLIC
#  CYTHON_IS_API
#
# If this is set of a *.pyx file with CMake set_source_files_properties()
# command, the file will be compiled as a C++ file.
#
# See also FindCython.cmake

#=============================================================================
# Copyright 2011 Kitware, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#=============================================================================

# Configuration options.
set(CYTHON_ANNOTATE OFF CACHE BOOL "Create an annotated .html file when compiling *.pyx.")
set(CYTHON_NO_DOCSTRINGS OFF CACHE BOOL "Strip docstrings from the compiled module.")
set(CYTHON_FLAGS "" CACHE STRING "Extra flags to the cython compiler.")
mark_as_advanced(CYTHON_ANNOTATE CYTHON_NO_DOCSTRINGS CYTHON_FLAGS)

find_package(Python3Alt REQUIRED)

# (using another C++ extension breaks coverage)
set(CYTHON_CXX_EXTENSION "cpp")
set(CYTHON_C_EXTENSION "c")

# Create a *.c or *.cpp file from a *.pyx file.
# Input the generated file basename.  The generate files will put into the variable
# placed in the "generated_files" argument. Finally all the *.py and *.pyx files.
function(compile_pyx
         _name
         pyx_target_name
         generated_files
         pyx_file)
  # Default to assuming all files are C.
  set(cxx_arg "")
  set(extension ${CYTHON_C_EXTENSION})
  set(pyx_lang "C")
  set(comment "Compiling Cython C source for ${_name}...")

  get_filename_component(pyx_file_basename "${pyx_file}" NAME_WE)

  # Determine if it is a C or C++ file.
  get_source_file_property(property_is_cxx ${pyx_file} CYTHON_IS_CXX)
  if(${property_is_cxx})
    set(cxx_arg "--cplus")
    set(extension ${CYTHON_CXX_EXTENSION})
    set(pyx_lang "CXX")
    set(comment "Compiling Cython CXX source for ${_name}...")
  endif()
  get_source_file_property(pyx_location ${pyx_file} LOCATION)

  set(output_file "${_name}.${extension}")

  # Set additional flags.
  if(CYTHON_ANNOTATE)
    set(annotate_arg "--annotate")
  endif()

  if(CYTHON_NO_DOCSTRINGS)
    set(no_docstrings_arg "--no-docstrings")
  endif()

  if(NOT WIN32)
    string( TOLOWER "${CMAKE_BUILD_TYPE}" build_type )
    if("${build_type}" STREQUAL "debug"
       OR "${build_type}" STREQUAL "relwithdebinfo")
      set(cython_debug_arg "--gdb")
    endif()
  endif()

  # Determining generated file names.
  get_source_file_property(property_is_public ${pyx_file} CYTHON_PUBLIC)
  get_source_file_property(property_is_api ${pyx_file} CYTHON_API)
  if(${property_is_api})
    set(_generated_files "${output_file}" "${_name}.h" "${_name}_api.h")
  elseif(${property_is_public})
    set(_generated_files "${output_file}" "${_name}.h")
  else()
    set(_generated_files "${output_file}")
  endif()
  set_source_files_properties(${_generated_files} PROPERTIES GENERATED TRUE)

  if(NOT WIN32)
    # Cython creates a lot of compiler warning detritus on clang
    set_source_files_properties(${_generated_files} PROPERTIES COMPILE_FLAGS
                                -Wno-unused-function)
  endif()

  set(${generated_files} ${_generated_files} PARENT_SCOPE)

  # Add the command to run the compiler.
  add_custom_target(
    ${pyx_target_name}
    COMMAND ${PYTHON_EXECUTABLE}
            -m
            cython
            ${cxx_arg}
            ${annotate_arg}
            ${no_docstrings_arg}
            ${cython_debug_arg}
            ${CYTHON_FLAGS}
            # Necessary for autodoc of function arguments
            --directive embedsignature=True
            # Necessary for Cython code coverage
            --working
            ${CMAKE_CURRENT_SOURCE_DIR}
            --output-file
            "${CMAKE_CURRENT_BINARY_DIR}/${output_file}"
            "${CMAKE_CURRENT_SOURCE_DIR}/${pyx_file}"
    DEPENDS ${pyx_location}
            # Do not specify byproducts for now since they don't work with the older
            # version of cmake available in the apt repositories.
            #BYPRODUCTS ${_generated_files}
    COMMENT ${comment})

  # Remove their visibility to the user.
  set(corresponding_pxd_file "" CACHE INTERNAL "")
  set(header_location "" CACHE INTERNAL "")
  set(pxd_location "" CACHE INTERNAL "")
endfunction()

# cython_add_module( <name> src1 src2 ... srcN )
# Build the Cython Python module.
function(cython_add_module _name pyx_target_name generated_files)
  set(pyx_module_source "")
  set(other_module_sources "")
  foreach(_file ${ARGN})
    if(${_file} MATCHES ".*\\.py[x]?$")
      list(APPEND pyx_module_source ${_file})
    else()
      list(APPEND other_module_sources ${_file})
    endif()
  endforeach()
  compile_pyx(${_name} ${pyx_target_name} _generated_files ${pyx_module_source})
  set(${generated_files} ${_generated_files} PARENT_SCOPE)
  include_directories(${PYTHON_INCLUDE_DIRS})
  python_add_module(${_name} ${_generated_files} ${other_module_sources})
  add_dependencies(${_name} ${pyx_target_name})
endfunction()

execute_process(COMMAND ${PYTHON_EXECUTABLE} -c "from Cython.Compiler.Version import version; print(version)"
                OUTPUT_VARIABLE CYTHON_VERSION_OUTPUT
                OUTPUT_STRIP_TRAILING_WHITESPACE)
set(CYTHON_VERSION "${CYTHON_VERSION_OUTPUT}")

include(CMakeParseArguments)
