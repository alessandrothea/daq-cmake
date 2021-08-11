
include(CMakePackageConfigHelpers)
include(GNUInstallDirs)
include(moo)

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

  set(CMAKE_CXX_STANDARD 17)
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

  # Insert a test/ directory one level up
  foreach(token LIB BIN SCHEMA CONFIG)
    string(REGEX REPLACE "(.*)(/[^/]+$)" "\\1/test\\2"  CMAKE_INSTALL_${token}_TESTDIR ${CMAKE_INSTALL_${token}DIR})
    #set(CMAKE_INSTALL_${token}_TESTDIR "/tmp")
  endforeach()

  set(DAQ_PROJECT_INSTALLS_TARGETS false)
  set(DAQ_PROJECT_GENERATES_CODE false)

  set(COMPILER_OPTS -g -pedantic -Wall -Wextra -fdiagnostics-color=always)
  if (${DBT_DEBUG})
    set(COMPILER_OPTS ${COMPILER_OPTS} -Og)
  else()
    set(COMPILER_OPTS ${COMPILER_OPTS} -O2)
  endif()
  add_compile_options(${COMPILER_OPTS})
  unset(COMPILER_OPTS)

  enable_testing()

  set(PRE_BUILD_STAGE_DONE_TRGT ${PROJECT_NAME}_pre_build_stage_done)
  add_custom_target(${PRE_BUILD_STAGE_DONE_TRGT} ALL)

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
#    Each schema file will applied to each template (specified by the TEMPLATE argument).
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
        message(WARNING "When defining list of schema files to perform code generation on, no files in ${CMAKE_CURRENT_SOURCE_DIR}/${schema_dir} match the glob \"${f}\"")
      endif()
    else()
       # may be generated file, so just add
      set(schemas ${schemas} ${schema_dir}/${PROJECT_NAME}/${f})
    endif()
  endforeach()

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
# daq_add_library:
# Usage:
# daq_add_library( <file | glob expression 1> ... [LINK_LIBRARIES <lib1> ...])
#
# daq_add_library is designed to produce the main library provided by
# a project for its dependencies to link in. It will compile a group
# of files defined by a set of one or more individual filenames and/or
# glob expressions, and link against the libraries listed after
# LINK_LIBRARIES. The set of files is assumed to be in the src/
# subdirectory of the project.
#
# As an example, 
# daq_add_library(MyProj.cpp *Utils.cpp LINK_LIBRARIES ers::ers) 
# will create a library off of src/MyProj.cpp and any file in src/
# ending in "Utils.cpp", and links against the ERS (Error Reporting
# System) library

# Public headers for users of the library should go in the project's
# include/<project name> directory. Private headers used in the
# library's implementation should be put in the src/ directory.

function(daq_add_library)

  cmake_parse_arguments(LIBOPTS "" "" "LINK_LIBRARIES" ${ARGN})

  set(libname ${PROJECT_NAME})

  set(LIB_PATH "src")

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
    add_library(${libname} SHARED ${libsrcs})
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

function(daq_add_plugin pluginname plugintype)

  cmake_parse_arguments(PLUGOPTS "TEST" "" "LINK_LIBRARIES" ${ARGN})

  set(pluginlibname "${PROJECT_NAME}_${pluginname}_${plugintype}")

  set(PLUGIN_PATH "plugins")
  if(${PLUGOPTS_TEST})
    set(PLUGIN_PATH "test/${PLUGIN_PATH}")
  endif()
  
  add_library( ${pluginlibname} MODULE ${PLUGIN_PATH}/${pluginname}.cpp)

  target_link_libraries(${pluginlibname} ${PLUGOPTS_LINK_LIBRARIES}) 
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
# expressions meant to build the executable. It expects the filenames
# to be either in the apps/ subdirectory of the project, or, if the
# "TEST" option is chosen, the test/apps/ subdirectory. Like
# daq_add_library, daq_add_application can be provided a list of
# libraries to link against, following the LINK_LIBRARIES token.

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
    else()
       # may be generated file, so just add
      set(appsrcs ${appsrcs} ${APP_PATH}/${f})
    endif()
  endforeach()

  
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
      PRIVATE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/test/src> $<BUILD_INTERFACE:${CMAKE_CODEGEN_BINARY_DIR}/test/src>
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

  add_executable( ${testname} ${UTEST_PATH}/${testname}.cxx )
  target_link_libraries( ${testname} ${UTEST_LINK_LIBRARIES} ${Boost_UNIT_TEST_FRAMEWORK_LIBRARY})
  target_compile_definitions(${testname} PRIVATE "BOOST_TEST_DYN_LINK=1")


  target_include_directories( ${testname} PRIVATE 
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/test/src>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/plugins>

    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/codegen/include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/codegen/test/src>
  )

  add_dependencies( ${testname} ${PRE_BUILD_STAGE_DONE_TRGT})

  add_test(NAME ${testname} COMMAND ${testname})

  _daq_set_target_output_dirs( ${testname} ${UTEST_PATH} )

endfunction()

function(daq_create_documentation)
    cmake_parse_arguments(DOXY "" "" "EXCLUDE;DEPENDS" ${ARGN})
    include(daq-Doxygen)
    create_doxygen_documentation(EXCLUDE ${DOXY_EXCLUDE} DEPENDS ${DOXY_DEPENDS})

endfunction()

####################################################################################################

# _daq_gather_info:
# Will take info both about the build and the source, and save it in a *.txt file 
# referred to by the variable DAQ_PROJECT_SUMMARY_FILENAME

macro(_daq_gather_info)

  set(DAQ_PROJECT_SUMMARY_FILENAME ${CMAKE_BINARY_DIR}/${PROJECT_NAME}_build_info.txt)

  set(dgi_cmds 
    "echo \"user for build:         $USER\""
    "echo \"hostname for build:     $HOSTNAME\""
    "echo \"build time:             `date`\""
    "echo \"local repo dir:         `pwd`\""
    "echo \"git branch:             `git branch | sed -r -n 's/^\\*.//p'`\""
    "echo \"git commit hash:        `git log --pretty=\"%H\" -1`\"" 
    "echo \"git commit time:        `git log --pretty=\"%ad\" -1`\""
    "echo \"git commit description: `git log --pretty=\"%s\" -1`\""
    "echo \"git commit author:      `git log --pretty=\"%an\" -1`\""
         "echo \"uncommitted changes:    `git diff HEAD --name-status | awk  '{print $2}' | sort -n | tr '\n' ' '`\""
    )

  set (dgi_fullcmd "")
  foreach( dgi_cmd ${dgi_cmds} )
    set(dgi_fullcmd "${dgi_fullcmd}${dgi_cmd}; ")
  endforeach()

  execute_process(COMMAND "bash" "-c" "${dgi_fullcmd}"  
              OUTPUT_FILE ${DAQ_PROJECT_SUMMARY_FILENAME}
              ERROR_FILE  ${DAQ_PROJECT_SUMMARY_FILENAME}
              WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
              )

endmacro()

####################################################################################################

# daq_install:
# Usage:
# daq_install()
#
# This function should be called at the bottom of a project's
# CMakeLists.txt file in order to install the project's targets. It takes no
# arguments.

function(daq_install) 

  _daq_gather_info()                  
  install(FILES ${DAQ_PROJECT_SUMMARY_FILENAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/${PROJECT_NAME})

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
  install(DIRECTORY cmake/ DESTINATION ${CMAKE_INSTALL_CMAKEDIR} FILES_MATCHING PATTERN "*.cmake")

  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/python/  DESTINATION ${CMAKE_INSTALL_PYTHONDIR} OPTIONAL FILES_MATCHING PATTERN "__pycache__" EXCLUDE PATTERN "*.py" )
  
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/scripts/ DESTINATION ${CMAKE_INSTALL_BINDIR} USE_SOURCE_PERMISSIONS OPTIONAL)
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test/scripts/ DESTINATION ${CMAKE_INSTALL_BIN_TESTDIR} USE_SOURCE_PERMISSIONS OPTIONAL)

  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/schema/  DESTINATION ${CMAKE_INSTALL_SCHEMADIR} OPTIONAL FILES_MATCHING PATTERN "*.jsonnet" PATTERN "*.j2")
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test/schema/  DESTINATION ${CMAKE_INSTALL_SCHEMA_TESTDIR} OPTIONAL FILES_MATCHING PATTERN "*.jsonnet" PATTERN "*.j2")

  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/config/  DESTINATION ${CMAKE_INSTALL_CONFIGDIR} OPTIONAL)
  install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test/config/  DESTINATION ${CMAKE_INSTALL_CONFIG_TESTDIR} OPTIONAL)

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
