
include(CMakePackageConfigHelpers)
include(GNUInstallDirs)
include(moo)

####################################################################################################
# _daq_gather_info:
# Usage:
# _daq_gather_info()

# Will take info both about the build and the source, and save it in a *.json file
# referred to by the variable CI_DAQ_PROJECT_SUMMARY_FILENAME

function(_daq_gather_info)

  cmake_parse_arguments(GI "" "TARGET;SUMMARY_FILE" "" ${ARGN})
  # TEMPLATES is mandatory
  if (NOT DEFINED GI_TARGET)
    message(FATAL_ERROR "ERROR: undefined TARGET argument.")
  endif()

  set(SUMMARY_FILEPATH ${CMAKE_CURRENT_BINARY_DIR}/${GI_SUMMARY_FILE})
  set(DAQ_PROJECT_SUMMARY_PHONY_TARGET phony_${PROJECT_NAME}_build_info.json)


  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/gather_info
  "#!/usr/bin/env bash
cat << EOF > ${SUMMARY_FILEPATH}
{
\"user for build\":         \"$(whoami)\",
\"hostname for build\":     \"$(hostname)\",
\"build time\":             \"$(date)\",
\"local repo dir\":         \"$(pwd)\",
\"git branch\":             \"$( (git rev-parse 2>/dev/null && git branch | sed -r -n 's/^\\*.//p') || echo 'no git repo found' )\",
\"git commit hash\":        \"$( (git rev-parse 2>/dev/null && git log --pretty=\"%H\" -1)  || echo 'no git repo found' )\",
\"git commit time\":        \"$( (git rev-parse 2>/dev/null && git log --pretty=\"%ad\" -1)  || echo 'no git repo found' )\",
\"git commit description\": \"$( (git rev-parse 2>/dev/null && git log --pretty=\"%s\" -1 | sed -r 's/\"/\\\\\"/g' ) || echo 'no git repo found' )\",
\"git commit author\":      \"$( (git rev-parse 2>/dev/null && git log --pretty=\"%an\" -1)  || echo 'no git repo found' )\",
\"uncommitted changes\":    \"$( (git rev-parse 2>/dev/null && git diff HEAD --name-status | awk  '{print $2}' | sort -n | tr '\\n' ' ' ) || echo 'no git repo found')\"
}
EOF
YELLOW=\"\\033[0;33m\"
PURPLE=\"\\033[0;35m\"
NC=\"\\033[0m\"
git rev-parse --is-inside-work-tree > /dev/null 2>&1|| printf \"\${YELLOW}Warning: local source code directory \${PURPLE}\$(pwd)\${YELLOW} is not inside a git repo work tree.\${NC}\n\"

")


  add_custom_command(
    OUTPUT ${DAQ_PROJECT_SUMMARY_PHONY_TARGET}
    COMMAND "bash" "${CMAKE_CURRENT_BINARY_DIR}/gather_info"
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
    )
  add_custom_target( ${GI_TARGET} ALL DEPENDS ${DAQ_PROJECT_SUMMARY_PHONY_TARGET} )

endfunction()


####################################################################################################

# daq_setup_environment:
# Usage:
# daq_setup_environment()
#
# This macro should be called immediately after this DAQ module is
# included in your DUNE DAQ project's CMakeLists.txt file; it ensures
# that DUNE DAQ projects all have a common build environment. It takes
# no arguments.

macro(daq_setup_environment)

  set(CMAKE_CXX_STANDARD 20)
  set(CMAKE_CXX_EXTENSIONS OFF)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)

  set(BUILD_SHARED_LIBS ON)

  # Include directories within CMAKE_SOURCE_DIR and CMAKE_BINARY_DIR should take precedence over everything else
  set(CMAKE_INCLUDE_DIRECTORIES_PROJECT_BEFORE ON)

  # All code for the project should be able to see the project's public include directory
  include_directories( ${CMAKE_CURRENT_SOURCE_DIR}/include )

  # Needed for clang-tidy (called by our linters) to work
  set(CMAKE_EXPORT_COMPILE_COMMANDS ON)


  set(CMAKE_CODEGEN_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/codegen")

  set(CMAKE_INSTALL_CMAKEDIR   ${CMAKE_INSTALL_LIBDIR}/${PROJECT_NAME}/cmake ) # Not defined in GNUInstallDirs
  set(CMAKE_INSTALL_PYTHONDIR  ${CMAKE_INSTALL_LIBDIR}/python ) # Not defined in GNUInstallDirs
  set(CMAKE_INSTALL_SCHEMADIR  ${CMAKE_INSTALL_DATADIR}/schema ) # Not defined in GNUInstallDirs
  set(CMAKE_INSTALL_CONFIGDIR  ${CMAKE_INSTALL_DATADIR}/config ) # Not defined in GNUInstallDirs
  set(CMAKE_INSTALL_INTEGTESTDIR ${CMAKE_INSTALL_DATADIR}/integtest ) # Not defined in GNUInstallDirs

  # Insert a test/ directory one level up
  foreach(token LIB BIN SCHEMA CONFIG)
    string(REGEX REPLACE "(.*)(/[^/]+$)" "\\1/test\\2"  CMAKE_INSTALL_${token}_TESTDIR ${CMAKE_INSTALL_${token}DIR})
    #set(CMAKE_INSTALL_${token}_TESTDIR "/tmp")
  endforeach()

  set(DAQ_PROJECT_INSTALLS_TARGETS false)
  set(DAQ_PROJECT_GENERATES_CODE false)
  set(DAQ_PROJECT_GENERATES_GRPC false)

  set(COMPILER_OPTS -g -pedantic -Wall -Wextra -Wnon-virtual-dtor -fdiagnostics-color=always)

  if (${DBT_DEBUG})
    set(COMPILER_OPTS ${COMPILER_OPTS} -Og)
  elseif(DEFINED DBT_OPTIMIZE_FLAG AND NOT DBT_OPTIMIZE_FLAG STREQUAL "None" )
    set(COMPILER_OPTS ${COMPILER_OPTS} "-${DBT_OPTIMIZE_FLAG}")
  else()
    set(COMPILER_OPTS ${COMPILER_OPTS} -O2)
  endif()

  add_compile_options(${COMPILER_OPTS})
  unset(COMPILER_OPTS)

  enable_testing()

  set(PRE_BUILD_STAGE_DONE_TRGT ${PROJECT_NAME}_pre_build_stage_done)
  add_custom_target(${PRE_BUILD_STAGE_DONE_TRGT} ALL)

  set(DAQ_PROJECT_SUMMARY_FILENAME ${PROJECT_NAME}_build_info.json)

  _daq_gather_info( TARGET ${PROJECT_NAME}_build_info SUMMARY_FILE ${DAQ_PROJECT_SUMMARY_FILENAME} )
  add_dependencies( ${PRE_BUILD_STAGE_DONE_TRGT} ${PROJECT_NAME}_build_info )

endmacro()


####################################################################################################
# _daq_set_target_output_dirs
# This utility function updates the target output properties and points
# them to the chosen project subdirectory in the build directory tree.
macro( _daq_set_target_output_dirs target output_dir )
  set_target_properties(${target}
    PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${output_dir}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${output_dir}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${output_dir}"
  )

endmacro()

####################################################################################################
macro( _daq_define_exportname )
  set( DAQ_PROJECT_EXPORTNAME ${PROJECT_NAME}Targets )
endmacro()


####################################################################################################
# daq_codegen:
# Usage:
# daq_codegen( <schema filename1> ... [TEST] [DEP_PKGS <package 1> ...] [MODEL <model filename>]
#              [TEMPLATES <template filename1> ...] )
#
#`daq_codegen` uses `moo` to generate C++ headers from schema files from schema/<package> applying
# them to one or more templates.
#
# Arguments:
#    <schema filename1> ...: The list of schema files to process from <package>/schema/<package>.
#    Each schema file will applied to each template (specified by the TEMPLATES argument).
#    Each schema/template pair will generate a code file named
#       build/<package>/codegen/include/<package>/<schema minus *.jsonnet extension>/<template minus *.j2 extension>
#    e.g. my_schema.jsonnet (from my_pkg) + your_pkg/YourStruct.hpp.j2 will result in
#        build/my_pkg/codegen/include/my_pkg/my_schema/YourStruct.hpp
#
#    TEST: If the code is meant for an entity in the package's test/ subdirectory, "TEST"
#      should be passed as an argument, and the schema file's path will be assumed to be
#      "test/schema/" rather than merely "schema/".
#
#    DEP_PKGS: If schema, template or model files depend on files provided by other DAQ packages,
#      the "DEP_PKGS" argument must contain the list of packages.
#
#    MODEL: The MODEL argument is # optional; if no model file name is explicitly provided,
#      omodel.jsonnet from the moo package itself is used.
#
#    TEMPLATES: The list of templates to use. This is a mandatory argument. The template file format is
#        <template package>/<template name including *.j2 extension>
#      If <template package> is omitted, the template is expected to be made available by moo.
#


function(daq_codegen)

  cmake_parse_arguments(CGOPTS "TEST" "MODEL" "DEP_PKGS;TEMPLATES" ${ARGN})

  # insert test in schema_dir if a TEST schema
  set(schema_dir "${PROJECT_SOURCE_DIR}")
  if (${CGOPTS_TEST})
    set(schema_dir "${schema_dir}/test")
  endif()
  set(schema_dir  "${schema_dir}/schema")

  # TEMPLATES is mandatory
  if (NOT DEFINED CGOPTS_TEMPLATES)
    message(FATAL_ERROR "ERROR: No template defined.")
  endif()

  # Fall back on omodel.jsonnet if no model is defined
  if (NOT DEFINED CGOPTS_MODEL)
    set(CGOPTS_MODEL omodel.jsonnet)
  endif()

  # Build the list of module paths
  set(dep_paths ${schema_dir})
  if (DEFINED CGOPTS_DEP_PKGS)
    foreach(dep_pkg ${CGOPTS_DEP_PKGS})

      if (EXISTS ${CMAKE_SOURCE_DIR}/${dep_pkg})
        list(APPEND dep_paths "${CMAKE_SOURCE_DIR}/${dep_pkg}/schema")
      else()

        if (NOT DEFINED "${dep_pkg}_DAQSHARE")
          if (NOT DEFINED "${dep_pkg}_CONFIG")
            message(FATAL_ERROR "ERROR: package ${dep_pkg} not found/imported.")
          else()
            message(FATAL_ERROR "ERROR: package ${dep_pkg} does not provide the ${dep_pkg}_DAQSHARE path variable.")
          endif()
        endif()

        list(APPEND dep_paths "${${dep_pkg}_DAQSHARE}/schema")
      endif()

      # message(NOTICE "${PROJECT_NAME} mpath ${dep_paths}")
    endforeach()
  endif()

  # Expect <pkgA>/<templA.ext.j2> <pkgB>/<templB.ext.j2> Struct.hpp.j2
  # -> outfiles = templA.ext templB.ext Struct.hpp
  # -> templates = pkgA/templA.ext.j2 pkgB/templB.ext.j2 ostruct.hpp.j2
  set(outfiles)
  set(templates)
  foreach(tname ${CGOPTS_TEMPLATES})
    get_filename_component(tbase ${tname} NAME)
    get_filename_component(tdir ${tname} DIRECTORY)
    get_filename_component(text ${tname} LAST_EXT)
    get_filename_component(tout ${tname} NAME_WLE)

    if (NOT "${text}" STREQUAL ".j2")
      message(FATAL_ERROR "ERROR: ${tname} is not a jinja template. '${text}' ")
    endif()

    # Fall back on moo templates if the template has no "namespace"
    if ("${tdir}" STREQUAL "")
      string(TOLOWER ${tname} tname_lc)
      list(APPEND templates "o${tname_lc}")
    else()
      list(APPEND templates ${tname})
    endif()

    list(APPEND outfiles ${tout})
  endforeach()


  # Resolve the list of schema files
  set(schemas)
  foreach(f ${CGOPTS_UNPARSED_ARGUMENTS})

    if(${f} MATCHES ".*\\*.*")  # An argument with an "*" in it is treated as a glob

      set(fpaths)
      file(GLOB fpaths CONFIGURE_DEPENDS ${schema_dir}/${PROJECT_NAME}/${f})

      if (fpaths)
        set(schemas ${schemas} ${fpaths})
      else()
        message(WARNING "When defining list of schema files to perform code generation on, no files in ${schema_dir}/${PROJECT_NAME} match the glob \"${f}\"")
      endif()
    else()
       # may be generated file, so just add
      set(schemas ${schemas} ${schema_dir}/${PROJECT_NAME}/${f})
    endif()
  endforeach()

  if (NOT schemas)
    message(FATAL_ERROR "ERROR: list of files/globs passed to daq_codegen don't match any existing files")
  endif()

  # Generate!
  foreach(schema_path ${schemas})
    string(REPLACE "${schema_dir}/" "" schema_file "${schema_path}")

    if (NOT EXISTS ${schema_path})
      message(FATAL_ERROR "ERROR: auto-generation of schema-based headers from \"${schema_file}\" failed because ${schema_path} could not be found")
    endif()

    get_filename_component(schema ${schema_file} NAME_WE)

    foreach(outfile templfile IN ZIP_LISTS outfiles templates)
      # message(NOTICE ${schema} ${outfile} ${templfile})

      # define the output dir
      set(outdir "${CMAKE_CODEGEN_BINARY_DIR}")
      if (${CGOPTS_TEST})
        set(outdir "${outdir}/test/src")
      else()
        set(outdir "${outdir}/include")
      endif()
      set(outdir "${outdir}/${PROJECT_NAME}/${schema}")


      if (NOT EXISTS ${outdir})
        message(NOTICE "Creating ${outdir} to hold moo-generated plugin headers for ${schema_file} since it doesn't yet exist")
        file(MAKE_DIRECTORY ${outdir})
      endif()

      # Convenience variable
      set(outpath ${outdir}/${outfile})


      # Make up a target name
      string(REPLACE "${CMAKE_CURRENT_BINARY_DIR}" "" moo_target ${outpath})
      string(REGEX REPLACE "[\./-]" "_" moo_target "moo_${PROJECT_NAME}${moo_target}")

      # Creare a unique file for dependency tracking
      string(REGEX REPLACE "[^a-zA-Z0-9]" "_" codedeps_filename "moo_render__${schema_file}__${model}__${templ_pkg}_${templfile}")


      # Run moo
      moo_render(
        TARGET ${moo_target}
        MPATH "${dep_paths}"
        TPATH "${dep_paths}"
        GRAFT /lang:ocpp.jsonnet
        TLAS  path=dunedaq.${PROJECT_NAME}.${schema}
              ctxpath=dunedaq
              os=${schema_file}
        MODEL ${CGOPTS_MODEL}
        TEMPL ${templfile}
        CODEGEN ${outpath}
        CODEDEP ${schema_dir}/${schema_file}
        DEPS_DIR ${CMAKE_CODEGEN_BINARY_DIR}/deps
      )
    add_dependencies( ${PRE_BUILD_STAGE_DONE_TRGT} ${moo_target})

    endforeach()

  endforeach()

  set(DAQ_PROJECT_GENERATES_CODE true PARENT_SCOPE)
endfunction()

####################################################################################################
# daq_protobuf_codegen:
# Usage:
# daq_protobuf_codegen( <protobuf filename1> ... [TEST] [GEN_GRPC] [DEP_PKGS <package 1> ...] )
#
# Arguments:
#    <protobuf filename1> ...: The list of *.proto files for protobuf's "protoc" program to process from <package>/schema/<package>. Globs also allowed.
#
#
#    TEST: If the code is meant for an entity in the package's test/ subdirectory, "TEST"
#      should be passed as an argument, and the schema file's path will be assumed to be
#      "test/schema/" rather than merely "schema/".
#
#    GEN_GRPC: if you need to have grpc file generated too
#      Note that this option will require you to have a find_package(gRPC REQUIRED) before calling this function if you choose to generate gRPC protofiles.
#
#    DEP_PKGS: if a *.proto file given depends on *.proto files provided by other DAQ packages,
#      the "DEP_PKGS" argument must contain the list of packages.
#
# Each *.proto file will have a C++ header/source file generated as
# well as a Python file. The header will be installed in the public
# include directory. The source file will be built as part of the main
# package library.
#
# Two requirements for calling this function:
# 1) You need to call find_package(Protobuf REQUIRED) to make the protobuf library available
# 2) You also need to call daq_add_library, i.e., have a main packagewide library

function (daq_protobuf_codegen)

  cmake_parse_arguments(PROTOBUFOPTS "TEST;GEN_GRPC" "" "DEP_PKGS" ${ARGN})
  
  # insert test in schema_dir if a TEST schema
  set(schema_dir "${PROJECT_SOURCE_DIR}")
  if (${PROTOBUFOPTS_TEST})
    set(schema_dir "${schema_dir}/test")
  endif()
  set(schema_dir  "${schema_dir}/schema")

  set(protofiles)

  foreach(f ${PROTOBUFOPTS_UNPARSED_ARGUMENTS})
    if(${f} MATCHES ".*\\*.*")  # An argument with an "*" in it is treated as a glob

      set(fpaths)
      file(GLOB fpaths CONFIGURE_DEPENDS ${schema_dir}/${PROJECT_NAME}/${f})

      if (fpaths)
        set(protofiles ${protofiles} ${fpaths})
      else()
        message(WARNING "When defining list of *.proto files to perform code generation on, no files in ${schema_dir} match the glob \"${f}\"")
      endif()
    else()
      set(protofiles ${protofiles} ${schema_dir}/${PROJECT_NAME}/${f})
    endif()
  endforeach()

  # Build the list of schema paths for this package and any packages which may have been specified to DEP_PKGS

  set(dep_paths ${schema_dir})
  if (DEFINED PROTOBUFOPTS_DEP_PKGS)
    foreach(dep_pkg ${PROTOBUFOPTS_DEP_PKGS})

      if (EXISTS ${CMAKE_SOURCE_DIR}/${dep_pkg})
        list(APPEND dep_paths "${CMAKE_SOURCE_DIR}/${dep_pkg}/schema")
      else()
        # message(NOTICE "${PROJECT_NAME} dep_pkg ${dep_pkg}")
        if (NOT DEFINED "${dep_pkg}_DAQSHARE")
          if (NOT DEFINED "${dep_pkg}_CONFIG")
            message(FATAL_ERROR "ERROR: package ${dep_pkg} not found/imported.")
          else()
            message(FATAL_ERROR "ERROR: package ${dep_pkg} does not provide the ${dep_pkg}_DAQSHARE path variable.")
          endif()
        endif()

        list(APPEND dep_paths "${${dep_pkg}_DAQSHARE}/schema")
      endif()

    endforeach()
  endif()

  set(outfiles)

  if (NOT protofiles)
    message(FATAL_ERROR "ERROR: list of files/globs passed to daq_protobuf_codegen don't match any existing files")
  endif()
  
  # define the output dir
  set(outdir "${CMAKE_CODEGEN_BINARY_DIR}")
  if (${PROTOBUFOPTS_TEST})
    set(outdir "${outdir}/test")
  endif()
  set(outinc "${outdir}/include")
  set(outdir "${outinc}/${PROJECT_NAME}")

  foreach(protofile ${protofiles})
    get_filename_component(basename ${protofile} NAME_WE)

    string(LENGTH "${schema_dir}/${PROJECT_NAME}/" base_dir_length)
    string(SUBSTRING ${protofile} ${base_dir_length} -1 relname)
    get_filename_component(reldir ${relname} DIRECTORY)

    # It's admittedly a bit inelegant to have not only a header but
    # also a source file appear in an include directory. However
    # there's currently no way to get protoc to output the header and
    # source files into separate directories, and attempts to do so
    # manually via a "COMMAND mv ..." in add_custom_command fail
    # because the "&&"ing of the commands means you get an error since
    # the output files from protoc don't yet exist
    

    list(APPEND outfiles ${outdir}/${reldir}/${basename}.pb.cc ${outdir}/${reldir}/${basename}.pb.h )

    if (${PROTOBUFOPTS_GEN_GRPC})
      list(APPEND outfiles ${outdir}/${reldir}/${basename}.grpc.pb.cc ${outdir}/${reldir}/${basename}.grpc.pb.h )
    endif()

  endforeach()

  set(protoc_includes)
  foreach (dep_path ${dep_paths})
    list(APPEND protoc_includes "-I${dep_path}")
  endforeach()

  if (NOT EXISTS ${outdir})
    file(MAKE_DIRECTORY ${outdir})
  endif()

  if (${PROTOBUFOPTS_GEN_GRPC})

    add_custom_command(
      OUTPUT ${outfiles}

      COMMAND ${PROTOBUF_PROTOC_EXECUTABLE}
              ${protoc_includes}
              --cpp_out=${outinc}
              --grpc_out=${outinc}
              --plugin=protoc-gen-grpc=`which grpc_cpp_plugin`
              ${protofiles}

      COMMAND ${PROTOBUF_PROTOC_EXECUTABLE}
              ${protoc_includes}
              --python_out=${outinc}
              --grpc_out=${outinc}
              --plugin=protoc-gen-grpc=`which grpc_python_plugin`
              ${protofiles}

      DEPENDS ${protofiles}
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    )
    set(DAQ_PROJECT_GENERATES_GRPC true PARENT_SCOPE)
  else()

    add_custom_command(
      OUTPUT ${outfiles}

      COMMAND ${PROTOBUF_PROTOC_EXECUTABLE}
              ${protoc_includes}
              --cpp_out=${outinc}
              --python_out=${outinc}
              ${protofiles}

      DEPENDS ${protofiles}
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    )

  endif()

  add_custom_target(${PROJECT_NAME}_PROTOBUF_GENERATION DEPENDS ${outfiles}  )
  add_dependencies( ${PRE_BUILD_STAGE_DONE_TRGT} ${PROJECT_NAME}_PROTOBUF_GENERATION)

  set(DAQ_PROJECT_GENERATES_CODE true PARENT_SCOPE)
  set(PROTOBUF_FILES ${outfiles} PARENT_SCOPE)

endfunction()

# ######################################################################
# daq_oks_codegen(<oks schema filename1> ... 
#                      [NAMESPACE ns]
#                      [DALDIR subdir]
#		       [DEP_PKGS pkg1 pkg2 ...]
#
# `daq_oks_codegen` uses the oksdalgen package's application of the same
# name to generate C++ and Python code from the OKS schema file(s)
# provided to it.
#
# Arguments:
#  <schema filename1> ...: the list of OKS schema files to process from `<package>/schema/<package>`. 
#
# TEST: If the code is meant for an entity in the package's test/ subdirectory, "TEST"
#  should be passed as an argument, and the schema file's path will be assumed to be
#  "test/schema/" rather than merely "schema/".
#
# NAMESPACE: the namespace in which the generated C++ classes will be in. Defaults to `dunedaq::<package>`
#
# DALDIR: subdirectory relative to the package's primary include directory where headers will appear (`include/<package>/<DALDIR argument>`); default is no subdirectory
#
# DEP_PKGS: if a schema file you've provided as an argument itself includes a schema file (or schema files) from one or more other packages, you need to supply the names of the packages as arguments to DEP_PKGS. 
#
#
# The generated code is automatically built into the package's main
# library (i.e., you don't need to explicitly pass the names of the
# generated files to `daq_add_library`). Note that you get an error if
# you call `daq_oks_codegen` and don't also call `daq_add_library`. 
#
#
#######################################################################

function(daq_oks_codegen)

   cmake_parse_arguments(config_opts "TEST" "NAMESPACE;DALDIR" "DEP_PKGS" ${ARGN})

   set(srcs ${config_opts_UNPARSED_ARGUMENTS})

   set(TARGETNAME DAL_${PROJECT_NAME})
   if(${config_opts_TEST})
     set(TARGETNAME ${TARGETNAME}_TEST)
   endif()

   if(TARGET ${TARGETNAME})
     message(FATAL_ERROR "You are using more than one daq_oks_codegen() command inside this package; this is not allowed. Exiting...")
   endif()

   if (NOT DEFINED OKSDALGEN_BINARY) 
     message(FATAL_ERROR "In order to call this function (daq_oks_codegen) you need to load the oksdalgen package in your CMakeLists.txt file via the find_package call")
   endif()

   set(LIST OKSDALGEN_INCLUDES ${CMAKE_CURRENT_BINARY_DIR}/oksdalgen_${TARGETNAME}/ )

   set(hpp_dir_prefix ${CMAKE_CODEGEN_BINARY_DIR} )
  if (${config_opts_TEST})
    set(hpp_dir_prefix "${hpp_dir_prefix}/test")
  endif()
  set(hpp_dir_prefix "${hpp_dir_prefix}/include")


   set(hpp_dir_relative ${PROJECT_NAME})
   if(config_opts_DALDIR)
     if(config_opts_DALDIR MATCHES "^${PROJECT_NAME}/")
       message(WARNING "The DALDIR subdirectory passed to this function begins with \"${PROJECT_NAME}/\"; this is probably not what you want as the subdirectory is taken as relative to ${hpp_dir_prefix}/${hpp_dir_relative}")
     endif()

     set(hpp_dir_relative ${hpp_dir_relative}/${config_opts_DALDIR})
   endif()

   set(hpp_dir ${hpp_dir_prefix}/${hpp_dir_relative})
   set(cpp_dir ${CMAKE_CODEGEN_BINARY_DIR}/src)
  if (${config_opts_TEST})
    set(cpp_dir "${CMAKE_CODEGEN_BINARY_DIR}/test/src")
  endif()

   set(NAMESPACE)
   if(NOT config_opts_NAMESPACE)
      set(NAMESPACE dunedaq::${PROJECT_NAME})
   else()
      set(NAMESPACE ${config_opts_NAMESPACE})
   endif()

   set(config_dependencies)

   set(dep_paths ${CMAKE_CURRENT_SOURCE_DIR} )

   if (DEFINED config_opts_DEP_PKGS)
     foreach(dep_pkg ${config_opts_DEP_PKGS})

       if (EXISTS ${CMAKE_SOURCE_DIR}/${dep_pkg})
         list(APPEND config_dependencies DAL_${dep_pkg})
         list(APPEND dep_paths "${CMAKE_SOURCE_DIR}/${dep_pkg}")
         list(APPEND OKSDALGEN_INCLUDES ${CMAKE_CURRENT_BINARY_DIR}/../${dep_pkg}/oksdalgen_DAL_${dep_pkg} )
       else()      					
         if (NOT DEFINED "${dep_pkg}_DAQSHARE")
           if (NOT DEFINED "${dep_pkg}_CONFIG")
             message(FATAL_ERROR "ERROR: package ${dep_pkg} not found/imported.")
           else()
             message(FATAL_ERROR "ERROR: package ${dep_pkg} does not provide the ${dep_pkg}_DAQSHARE path variable.")
           endif()
         endif()
        
         list(APPEND dep_paths "${${dep_pkg}_DAQSHARE}")
         list(APPEND OKSDALGEN_INCLUDES "${${dep_pkg}_DAQSHARE}/oksdalgen_DAL_${dep_pkg}")
       endif()
     endforeach()
   endif()

   set(schemas)
  # insert test in schema_dir if a TEST schema
  set(schema_dir "${PROJECT_SOURCE_DIR}")
  if (${config_opts_TEST})
    set(schema_dir "${schema_dir}/test")
  endif()
  set(schema_dir  "${schema_dir}/schema")
   foreach(src ${srcs})
     set(schemas ${schemas} ${schema_dir}/${PROJECT_NAME}/${src})
   endforeach()
   
   foreach(schema ${schemas}) 

     execute_process(
       COMMAND grep "[ \t]*<class name=\"" ${schema}
       COMMAND sed "s;[ \t]*<class name=\";;"
       COMMAND sed s:\".*::
       COMMAND tr "\\n" " "
       OUTPUT_VARIABLE class_out 
       )

     separate_arguments(class_out)

     foreach(s ${class_out})
       set(cpp_source ${cpp_source} ${cpp_dir}/${s}.cpp ${hpp_dir}/${s}.hpp)
     endforeach()

   endforeach()
   
   separate_arguments(cpp_source)

   if (NOT TARGET oksdalgen)
     add_custom_target( oksdalgen )
     add_dependencies( oksdalgen oksdalgen::oksdalgen)
   endif()

   set(OKSDALGEN_DEPENDS oksdalgen)

   # JCF, Apr-16-2024: since DUNEDAQ_DB_PATH contains source directories,
   # the following statement (and the workaround it justifies) may no longer
   # be necessary:
   
   # Notice we need to locally-override DUNEDAQ_DB_PATH since this
   # variable typically refers to installed directories, but
   # installation only happens after building is complete
   
   string(JOIN ":" PATHS_TO_SEARCH ${dep_paths})

   if (NOT EXISTS ${hpp_dir})
     file(MAKE_DIRECTORY ${hpp_dir})
   endif()

   add_custom_command(
     OUTPUT ${cpp_source} oksdalgen_${TARGETNAME}/oksdalgen.info 
     COMMAND mkdir -p ${cpp_dir} oksdalgen_${TARGETNAME}
     COMMAND ${CMAKE_COMMAND} -E env DUNEDAQ_DB_PATH=${PATHS_TO_SEARCH} ${OKSDALGEN_BINARY} -i ${hpp_dir_relative} -n ${NAMESPACE} -d ${cpp_dir} -I ${OKSDALGEN_INCLUDES} -s ${schemas}
     COMMAND cp -f ${cpp_dir}/*.hpp ${hpp_dir}/
     COMMAND cp oksdalgen.info oksdalgen_${TARGETNAME}/
     DEPENDS ${schemas} ${config_dependencies} ${OKSDALGEN_DEPENDS} 
)

   add_custom_target(${TARGETNAME} ALL DEPENDS ${cpp_source} oksdalgen_${TARGETNAME}/oksdalgen.info)
   add_dependencies( ${PRE_BUILD_STAGE_DONE_TRGT} ${TARGETNAME})

   install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/oksdalgen_${TARGETNAME} DESTINATION ${CMAKE_INSTALL_DATADIR})

  set(DAQ_PROJECT_INSTALLS_TARGETS true PARENT_SCOPE)
  set(DAQ_PROJECT_GENERATES_CODE true PARENT_SCOPE)
  if(NOT ${config_opts_TEST})
    set(ANY_OKS_FILES ${cpp_source} PARENT_SCOPE)
  else()
    set(TEST_OKS_FILES ${cpp_source} PARENT_SCOPE)
  endif()
  set(ANY_OKS_LIBS conffwk::conffwk PARENT_SCOPE)

endfunction()


####################################################################################################
# daq_add_library:
# Usage:
# daq_add_library( <file | glob expression 1> ... [LINK_LIBRARIES <lib1> ...])
#
# daq_add_library is designed to produce the main library provided by
# a project for its dependencies to link in. It will compile a group
# of files defined by a set of one or more individual filenames and/or
# glob expressions, and link against the libraries listed after
# LINK_LIBRARIES. The set of files is assumed to be in the src/
# subdirectory of the project unless a filename begins with "/" in
# which case the absolute path is used. Wildcards are not supported
# for absolute paths as the use case for absolute paths is passing
# generated files which are typically represented by a variable
# (e.g. ${list_of_qt_generated_files}).
#
# As an example,
# daq_add_library(MyProj.cpp *Utils.cpp LINK_LIBRARIES logging::logging)
# will create a library off of src/MyProj.cpp and any file in src/
# ending in "Utils.cpp", and links against the logging library (https://dune-daq-sw.readthedocs.io/en/latest/packages/logging/)

# Public headers for users of the library should go in the project's
# include/<project name> directory. Private headers used in the
# library's implementation should be put in the src/ directory.

function(daq_add_library)

  cmake_parse_arguments(LIBOPTS "" "" "LINK_LIBRARIES" ${ARGN})

  set(libname ${PROJECT_NAME})

  set(LIB_PATH "src")

  set(libsrcs ${ANY_OKS_FILES})
  foreach(f ${LIBOPTS_UNPARSED_ARGUMENTS})

    if(${f} MATCHES ".*\\*.*")  # An argument with an "*" in it is treated as a glob

      set(fpaths)
      file(GLOB fpaths CONFIGURE_DEPENDS ${LIB_PATH}/${f})

      if (fpaths)
        set(libsrcs ${libsrcs} ${fpaths})
      else()
        message(WARNING "When defining list of files from which to build library \"${libname}\", no files in ${CMAKE_CURRENT_SOURCE_DIR}/${LIB_PATH} match the glob \"${f}\"")
      endif()
    elseif(${f} MATCHES "^/[^*]+")
      set(libsrcs ${libsrcs} ${f})
    else()
       # may be generated file, so just add
      set(libsrcs ${libsrcs} ${LIB_PATH}/${f})
    endif()
  endforeach()

  set(libsrcs ${libsrcs} ${PROTOBUF_FILES})

  if (libsrcs)

    add_library(${libname} SHARED ${libsrcs})
    target_link_libraries(${libname} PUBLIC ${LIBOPTS_LINK_LIBRARIES} ${ANY_OKS_LIBS}) 

    if (EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/include)
      target_include_directories(${libname} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
      )
    endif()

    if (${DAQ_PROJECT_GENERATES_CODE})
      target_include_directories(${libname} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
      )
    endif()

    if (TARGET ${PROJECT_NAME}_PROTOBUF_GENERATION)

      if (NOT DEFINED Protobuf_INCLUDE_DIRS OR NOT DEFINED Protobuf_LIBRARY)
        message(FATAL_ERROR "It appears that find_package on the \"Protobuf\" package hasn't been called; this is needed given that this daq-cmake code arranges for code generation with this package")
      endif()

      target_include_directories(${libname} PUBLIC ${Protobuf_INCLUDE_DIRS})
      target_link_libraries(${libname} PUBLIC ${Protobuf_LIBRARY})

      if (${DAQ_PROJECT_GENERATES_GRPC})
        target_link_libraries(${libname} PUBLIC gRPC::grpc++)
      endif()

    endif()

    target_include_directories(${libname} PRIVATE
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    )

    add_dependencies( ${libname} ${PRE_BUILD_STAGE_DONE_TRGT})
    _daq_set_target_output_dirs( ${libname} ${LIB_PATH} )
  else()

    add_library(${libname} INTERFACE)
    target_link_libraries(${libname} INTERFACE ${LIBOPTS_LINK_LIBRARIES})

    if (EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/include)
      target_include_directories(${libname} INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
      )
    endif()

    if (${DAQ_PROJECT_GENERATES_CODE})
      target_include_directories(${libname} INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
      )
    endif()

    add_dependencies( ${libname} ${PRE_BUILD_STAGE_DONE_TRGT})

  endif()

  _daq_define_exportname()
  install(TARGETS ${libname} EXPORT ${DAQ_PROJECT_EXPORTNAME} )
  set(DAQ_PROJECT_INSTALLS_TARGETS true PARENT_SCOPE)

endfunction()


####################################################################################################
# daq_add_plugin:
# Usage:
# daq_add_plugin( <plugin name> <plugin type> [TEST] [LINK_LIBRARIES <lib1> ...] )
#

# daq_add_plugin will build a plugin of type <plugin type> with the
# user-defined name <plugin name>. It will expect that there's a file
# with the name <plugin name>.cpp located either in the plugins/
# subdirectory of the project (if the "TEST" option isn't used) or in
# the test/plugins/ subdirectory of the project (if it is). Like
# daq_add_library, daq_add_plugin can be provided a list of libraries
# to link against, following the LINK_LIBRARIES argument.

# Your plugin will look in include/ for your project's public headers
# and src/ for its private headers. Additionally, if it's a "TEST"
# plugin, it will look in test/src/.

# Note that if cetlib is a dependency of the package being built, it
# will be automatically linked against the plugin.

function(daq_add_plugin pluginname plugintype)

  cmake_parse_arguments(PLUGOPTS "TEST" "" "LINK_LIBRARIES" ${ARGN})

  set(pluginlibname "${PROJECT_NAME}_${pluginname}_${plugintype}")

  set(PLUGIN_PATH "plugins")
  if(${PLUGOPTS_TEST})
    set(PLUGIN_PATH "test/${PLUGIN_PATH}")
    set(test_srcs ${TEST_OKS_FILES})
  endif()

  add_library( ${pluginlibname} MODULE ${PLUGIN_PATH}/${pluginname}.cpp ${test_srcs})
  target_link_options( ${pluginlibname} PRIVATE "LINKER:--no-undefined") # A plugin should have all its contents defined 

  if (NOT DEFINED CETLIB)
    target_link_libraries(${pluginlibname} ${PLUGOPTS_LINK_LIBRARIES})
  else()
    target_link_libraries(${pluginlibname} ${PLUGOPTS_LINK_LIBRARIES} ${CETLIB} ${CETLIB_EXCEPT})
  endif()

  target_include_directories(${pluginlibname} PRIVATE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/include>
  )
  add_dependencies( ${pluginlibname} ${PRE_BUILD_STAGE_DONE_TRGT})

  _daq_set_target_output_dirs( ${pluginlibname} ${PLUGIN_PATH} )
  _daq_define_exportname()

  if ( ${PLUGOPTS_TEST} )
    target_include_directories(${pluginlibname} PRIVATE
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/test/src>
      $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/test/src>
      $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/test/include>
  )
    install(TARGETS ${pluginlibname} EXPORT ${DAQ_PROJECT_EXPORTNAME} DESTINATION ${CMAKE_INSTALL_LIB_TESTDIR})
  else()
    install(TARGETS ${pluginlibname} EXPORT ${DAQ_PROJECT_EXPORTNAME} DESTINATION ${CMAKE_INSTALL_LIBDIR})
  endif()

  set(DAQ_PROJECT_INSTALLS_TARGETS true PARENT_SCOPE)

endfunction()

####################################################################################################
# daq_add_python_bindings:
# Usage:
# daq_add_python_bindings( <file | glob expression 1> ... [LINK_LIBRARIES <lib1> ...])
#
# daq_add_python_bindings is designed to produce a library providing
# a python interface to C++ code. It will compile a group
# of files, which are expected to expose the desired C++ interface via pybind11.
# The set of files is defined by a set of one or more individual filenames and/or
# glob expressions, and link against the libraries listed after
# LINK_LIBRARIES. The set of files is assumed to be in the pybindsrc/
# subdirectory of the project.
#
# As an example,
# daq_add_python_bindings(my_wrapper.cpp LINK_LIBRARIES ${PROJECT_NAME})
# will create a library from pybindsrc/my_wrapper.cpp and link against
# the main project library which would have been created via daq_add_library

# Please note that library shared object will be named _daq_${PROJECT_NAME}_py.so, and will be placed
# in the python/${PROJECT_NAME} directory. You will need to have the corresponding init file,
# python/${PROJECT_NAME}/__init__.py to import the appropiate componenets of the module.
# See toylibrary for a working example.

function(daq_add_python_bindings)

  cmake_parse_arguments(LIBOPTS "" "" "LINK_LIBRARIES" ${ARGN})

  set(libname _daq_${PROJECT_NAME}_py)

  set(LIB_PATH "pybindsrc")

  set(libsrcs)
  foreach(f ${LIBOPTS_UNPARSED_ARGUMENTS})

    if(${f} MATCHES ".*\\*.*")  # An argument with an "*" in it is treated as a glob

      set(fpaths)
      file(GLOB fpaths CONFIGURE_DEPENDS ${LIB_PATH}/${f})

      if (fpaths)
        set(libsrcs ${libsrcs} ${fpaths})
      else()
        message(WARNING "When defining list of files from which to build library \"${libname}\", no files in ${CMAKE_CURRENT_SOURCE_DIR}/${LIB_PATH} match the glob \"${f}\"")
      endif()
    else()
       # may be generated file, so just add
      set(libsrcs ${libsrcs} ${LIB_PATH}/${f})
    endif()
  endforeach()

  if (libsrcs)
    pybind11_add_module(${libname} ${libsrcs})
    target_link_libraries(${libname} PUBLIC ${LIBOPTS_LINK_LIBRARIES})

    if (EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/include)
      target_include_directories(${libname} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
      )
    endif()

    if (${DAQ_PROJECT_GENERATES_CODE})
      target_include_directories(${libname} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
      )
    endif()

    target_include_directories(${libname} PRIVATE
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    )
    set_target_properties(${libname} PROPERTIES SUFFIX ".so")

    add_dependencies( ${libname} ${PRE_BUILD_STAGE_DONE_TRGT})

    _daq_set_target_output_dirs( ${libname} python/${PROJECT_NAME} )
  else()
    message(FATAL_ERROR "ERROR: No source files found for python library: ${libname}.")
  endif()

  _daq_define_exportname()
  install(TARGETS ${libname} EXPORT ${DAQ_PROJECT_EXPORTNAME} DESTINATION ${CMAKE_INSTALL_PYTHONDIR}/${PROJECT_NAME})
  set(DAQ_PROJECT_INSTALLS_TARGETS true PARENT_SCOPE)

endfunction()

####################################################################################################
# daq_add_application:
# Usage:
# daq_add_application(<application name> <file | glob expression> ... [TEST] [LINK_LIBRARIES <lib1> ...])
#
# This function is designed to build a standalone application in your
# project. Its first argument is simply the desired name of the
# executable, followed by a list of filenames and/or file glob
# expressions meant to build the executable. When given relative paths
# for the filenames, it expects them to be to be either in the apps/
# subdirectory of the project, or, if the "TEST" option is chosen, the
# test/apps/ subdirectory. It will also accept full pathnames, but
# without wildcarding (see daq_add_library documentation for the
# reason). Like daq_add_library, daq_add_application can be provided a
# list of libraries to link against, following the LINK_LIBRARIES
# token.

# Your application will look in include/ for your project's public
# headers and src/ for its private headers. Additionally, if it's a
# "TEST" plugin, it will look in test/src/.

function(daq_add_application appname)

  cmake_parse_arguments(APPOPTS "TEST" "" "LINK_LIBRARIES" ${ARGN})

  set(APP_PATH "apps")
  if(${APPOPTS_TEST})
    set(APP_PATH "test/${APP_PATH}")
  endif()

  set(appsrcs)
  foreach(f ${APPOPTS_UNPARSED_ARGUMENTS})

    if(${f} MATCHES ".*\\*.*")   # An argument with an "*" in it is treated as a glob

      set(fpaths)
      file(GLOB fpaths CONFIGURE_DEPENDS ${APP_PATH}/${f})

      if (fpaths)
        set(appsrcs ${appsrcs} ${fpaths})
      else()
        message(WARNING "When defining list of files from which to build application \"${appname}\", no files in ${CMAKE_CURRENT_SOURCE_DIR}/${APP_PATH} match the glob \"${f}\"")
      endif()
    elseif(${f} MATCHES "^/[^*]+")
      set(appsrcs ${appsrcs} ${f})
    else()
       # may be generated file, so just add
      set(appsrcs ${appsrcs} ${APP_PATH}/${f})
    endif()
  endforeach()

  if(APPOPTS_TEST)
    set(appsrcs ${appsrcs} ${TEST_OKS_FILES})
  endif()

  add_executable(${appname} ${appsrcs})
  target_link_libraries(${appname} PUBLIC ${APPOPTS_LINK_LIBRARIES})
  # Add src to the include path for private headers
  target_include_directories( ${appname} PRIVATE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/include>
  )
  add_dependencies( ${appname} ${PRE_BUILD_STAGE_DONE_TRGT})

  _daq_set_target_output_dirs( ${appname} ${APP_PATH} )
  _daq_define_exportname()

  if( ${APPOPTS_TEST} )
    target_include_directories( ${appname}
      PRIVATE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/test/src> 
              $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/test/src>
              $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/test/include>
  )
    install(TARGETS ${appname} EXPORT ${DAQ_PROJECT_EXPORTNAME} DESTINATION ${CMAKE_INSTALL_BIN_TESTDIR})
  else()
    install(TARGETS ${appname} EXPORT ${DAQ_PROJECT_EXPORTNAME} DESTINATION ${CMAKE_INSTALL_BINDIR})
  endif()

  set(DAQ_PROJECT_INSTALLS_TARGETS true PARENT_SCOPE)

endfunction()


####################################################################################################
# daq_add_unit_test:
#
# Usage: daq_add_unit_test(<unit test name> [LINK_LIBRARIES <lib1> ...])
#
# This function, when given the extension-free name of a unit test
# sourcefile in unittest/, will handle the needed boost functionality
# to build the unit test, as well as provide other support (CTest,
# etc.). Like daq_add_library, daq_add_unit_test can be provided a
# list of libraries to link against, following the LINK_LIBRARIES
# token.
#

function(daq_add_unit_test testname)

  cmake_parse_arguments(UTEST "" "" "LINK_LIBRARIES" ${ARGN})

  set(UTEST_PATH "unittest")

  add_executable( ${testname} ${UTEST_PATH}/${testname}.cxx ${TEST_OKS_FILES})
  target_link_libraries( ${testname} ${UTEST_LINK_LIBRARIES} ${Boost_UNIT_TEST_FRAMEWORK_LIBRARY})
  target_compile_definitions(${testname} PRIVATE "BOOST_TEST_DYN_LINK=1")


  target_include_directories( ${testname} PRIVATE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/test/src>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/plugins>

    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/codegen/include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/codegen/test/src>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/codegen/test/include>
  )

  add_dependencies( ${testname} ${PRE_BUILD_STAGE_DONE_TRGT})

  add_test(NAME ${testname} COMMAND ${testname})

  _daq_set_target_output_dirs( ${testname} ${UTEST_PATH} )

endfunction()


####################################################################################################

# daq_install:
# Usage:
# daq_install()
#
# This function should be called at the bottom of a project's
# CMakeLists.txt file in order to install the project's targets. It takes no
# arguments.

function(daq_install)

  if (DEFINED PROTOBUF_FILES AND NOT TARGET ${PROJECT_NAME})
     message(FATAL_ERROR "Error in call to daq_protobuf_codegen: you need to also create a package-wide library via daq_add_library, since these functions will automatically compile the code daq_protobuf_codegen generates into such a library")
  endif()


  if (DEFINED ANY_OKS_FILES AND NOT TARGET ${PROJECT_NAME})
    message(FATAL_ERROR "Error in call to daq_oks_codegen; you need to also create a package-wide library via daq_add_library, since these functions will automatically compile the code daq_oks_codegen generates into such a library")
  endif()		      

  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${DAQ_PROJECT_SUMMARY_FILENAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/${PROJECT_NAME})

  ## AT HACK ALERT
  file(GLOB cmks CONFIGURE_DEPENDS cmake/*.cmake)
  foreach (cmk ${cmks})
    # repkace with configure_file?
    file(COPY ${cmk} DESTINATION ${CMAKE_CURRENT_BINARY_DIR})
  endforeach()
  ## AT HACK ALERT

  if (${DAQ_PROJECT_INSTALLS_TARGETS})
    _daq_define_exportname()
    install(EXPORT ${DAQ_PROJECT_EXPORTNAME} FILE ${DAQ_PROJECT_EXPORTNAME}.cmake NAMESPACE ${PROJECT_NAME}:: DESTINATION ${CMAKE_INSTALL_CMAKEDIR} )
  endif()

  install(DIRECTORY include/${PROJECT_NAME} DESTINATION ${CMAKE_INSTALL_INCLUDEDIR} FILES_MATCHING PATTERN "*.h??")
  install(DIRECTORY ${CMAKE_CODEGEN_BINARY_DIR}/include/${PROJECT_NAME} DESTINATION ${CMAKE_INSTALL_INCLUDEDIR} FILES_MATCHING PATTERN "*.h??")
  install(DIRECTORY ${CMAKE_CODEGEN_BINARY_DIR}/include/${PROJECT_NAME} DESTINATION ${CMAKE_INSTALL_INCLUDEDIR} FILES_MATCHING PATTERN "*.pb.h")
  install(DIRECTORY ${CMAKE_CODEGEN_BINARY_DIR}/include/${PROJECT_NAME} DESTINATION ${CMAKE_INSTALL_PYTHONDIR} FILES_MATCHING PATTERN "*.py")
  install(DIRECTORY cmake/ DESTINATION ${CMAKE_INSTALL_CMAKEDIR} FILES_MATCHING PATTERN "*.cmake")

  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/python/  DESTINATION ${CMAKE_INSTALL_PYTHONDIR} OPTIONAL FILES_MATCHING PATTERN "__pycache__" EXCLUDE PATTERN "*.py" )

  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/scripts/ DESTINATION ${CMAKE_INSTALL_BINDIR} USE_SOURCE_PERMISSIONS OPTIONAL)
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test/scripts/ DESTINATION ${CMAKE_INSTALL_BIN_TESTDIR} USE_SOURCE_PERMISSIONS OPTIONAL)

  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/schema/  DESTINATION ${CMAKE_INSTALL_SCHEMADIR} OPTIONAL FILES_MATCHING PATTERN "*.jsonnet" PATTERN "*.j2" PATTERN "*.xml" PATTERN "*.proto")
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test/schema/  DESTINATION ${CMAKE_INSTALL_SCHEMA_TESTDIR} OPTIONAL FILES_MATCHING PATTERN "*.jsonnet" PATTERN "*.j2" PATTERN "*.xml" PATTERN "*.proto")

  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/config/  DESTINATION ${CMAKE_INSTALL_CONFIGDIR} OPTIONAL)
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test/config/  DESTINATION ${CMAKE_INSTALL_CONFIG_TESTDIR} OPTIONAL)
                                                    
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/integtest/ DESTINATION ${CMAKE_INSTALL_INTEGTESTDIR} OPTIONAL)		    

  set(versionfile        ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake)
  set(configfiletemplate ${CMAKE_CURRENT_SOURCE_DIR}/cmake/${PROJECT_NAME}Config.cmake.in)
  set(configfile         ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Config.cmake)

  if (DEFINED PROJECT_VERSION)
    write_basic_package_version_file(${versionfile} COMPATIBILITY ExactVersion)
  else()
    message(FATAL_ERROR "ERROR: the PROJECT_VERSION CMake variable needs to be defined in order to install. The way to do this is by adding the version to the project() call at the top of your CMakeLists.txt file, e.g. \"project(${PROJECT_NAME} VERSION 1.0.0)\"")
  endif()

  if (EXISTS ${configfiletemplate})
    configure_package_config_file(${configfiletemplate} ${configfile} INSTALL_DESTINATION ${CMAKE_INSTALL_CMAKEDIR})
  else()
     message(FATAL_ERROR "ERROR: unable to find needed file ${configfiletemplate} for ${PROJECT_NAME} installation")
  endif()

  install(FILES ${versionfile} ${configfile} DESTINATION ${CMAKE_INSTALL_CMAKEDIR})

endfunction()

####################################################################################################
