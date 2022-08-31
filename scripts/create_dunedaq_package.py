#!/usr/bin/env python3

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys

if "DBT_ROOT" in os.environ:
    sys.path.append(f'{os.environ["DBT_ROOT"]}/scripts')
else:
    print("""
ERROR: daq-buildtools environment needs to be set up for this script to work. 
Exiting...""")
    sys.exit(1)

from dbt_setup_tools import error, get_time

usage_blurb=f"""
Usage
-----

This script generates much of the standard CMake/C++ code of a new
DUNE DAQ package. In general, the more you know about your package in
advance (e.g. whether it should contain DAQModules and what their
names should be, etc.) the more work this script can do for you.

Simplest usage:
{os.path.basename (__file__)} <name of new repo in DUNE-DAQ>\n\n")

...where the new repo must be empty with the exception of an optional README.md. 

Arguments and options:

--main-library: package will contain a main, package-wide library which other 
                packages can link in

--python-bindings: whether there will be Python bindings to components in a 
                   main library. Requires the --main-library option as well.

--daq-module: for each "--daq-module <module name>" provided at the command
              line, the framework for a DAQModule will be auto-generated

--user-app: same as --daq-module, but for user applications

--test-app: same as --daq-module, but for integration test applications

For details on how to write a DUNE DAQ package, please look at the official 
daq-cmake documentation at 
https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-cmake/

"""

parser = argparse.ArgumentParser(usage=usage_blurb)
parser.add_argument("--main-library", action="store_true", dest="contains_main_library", help=argparse.SUPPRESS)
parser.add_argument("--python-bindings", action="store_true", dest="contains_python_bindings", help=argparse.SUPPRESS)
parser.add_argument("--daq-module", action="append", dest="daq_modules", help=argparse.SUPPRESS)
parser.add_argument("--user-app", action="append", dest="user_apps", help=argparse.SUPPRESS)
parser.add_argument("--test-app", action="append", dest="test_apps", help=argparse.SUPPRESS)
parser.add_argument("package", nargs="?", help=argparse.SUPPRESS)

args = parser.parse_args()

if args.package is not None: 
    PACKAGE = args.package
else:
    print(usage_blurb)
    sys.exit(1)

if args.contains_python_bindings and not args.contains_main_library:
    error("""
To use the --python-bindings option you also need the --main-library option 
as you'll want python bindings to your package's main library.
""")

#PACKAGE_REPO = f"https://github.com/DUNE-DAQ/{package}/"
PACKAGE_REPO = f"https://github.com/jcfreeman2/{PACKAGE}/"  # jcfreeman2 is for testing purposes since there's no guaranteed-empty-repo in DUNE-DAQ

THIS_SCRIPTS_DIRECTORY=pathlib.Path(__file__).parent.resolve()
TEMPLATEDIR = f"{THIS_SCRIPTS_DIRECTORY}/templates"

if "DBT_AREA_ROOT" in os.environ:
    SOURCEDIR = os.environ["DBT_AREA_ROOT"] + "/sourcecode"
else:
    error("""
The environment variable DBT_AREA_ROOT doesn't appear to be defined. 
You need to have a work area environment set up for this script to work. 
Exiting...
""")


REPODIR = f"{SOURCEDIR}/{PACKAGE}"
os.chdir(f"{SOURCEDIR}")

proc = subprocess.Popen(f"git clone {PACKAGE_REPO}", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
proc.communicate()
RETVAL = proc.returncode

if RETVAL == 128:
    error(f"""
git was either unable to find a {PACKAGE_REPO} repository
or it already existed in {os.getcwd()}
and couldn't be overwritten
    """)
elif RETVAL != 0:
    error(f"Totally unexpected error (return value {RETVAL}) occurred when running \"git clone {PACKAGE_REPO}\"")

def cleanup(REPODIR):
    if os.path.exists(REPODIR):

        # This code is very cautious so that it rm -rf's the directory it expects 
        if re.search(f"/{PACKAGE}", REPODIR):
            shutil.rmtree(REPODIR)
        else:
            assert False, f"SCRIPT ERROR: This script does not trust that the directory \"{REPODIR}\" is something it should delete since it doesn't look like a local repo for {PACKAGE}"
    else:
        assert False, f"SCRIPT ERROR: This script is unable to locate the expected repo directory {REPODIR}"

def make_package_dir(dirname):
    os.makedirs(dirname, exist_ok=True)
    if not os.path.exists(f"{dirname}/.gitkeep"):
        open(f"{dirname}/.gitkeep", "w")

os.chdir(REPODIR)

if os.listdir(REPODIR) != [".git"] and sorted(os.listdir(REPODIR)) != [".git", "README.md"] and sorted(os.listdir(REPODIR)) != [".git", "docs"]:
    cleanup(REPODIR)
    error(f"""

Just ran \"git clone {PACKAGE_REPO}\", and it looks like this repo isn't empty. 
This script can only be run on repositories which haven't yet been worked on.
""")

find_package_calls = []
daq_codegen_calls = []
daq_add_library_calls = []
daq_add_python_bindings_calls = []
daq_add_plugin_calls = []
daq_add_application_calls = []
daq_add_unit_test_calls = []

print("")

if args.contains_main_library:
    make_package_dir(f"{REPODIR}/src")
    make_package_dir(f"{REPODIR}/include/{PACKAGE}")
    daq_add_library_calls.append("daq_add_library( LINK_LIBRARIES ) # Any source files and/or dependent libraries to link in not yet determined")

if args.contains_python_bindings:
    make_package_dir(f"{REPODIR}/pybindsrc")
    daq_add_python_bindings_calls.append("\ndaq_add_python_bindings(*.cpp LINK_LIBRARIES ${PROJECT_NAME} ) # Any additional libraries to link in beyond the main library not yet determined\n")

    for src_filename in ["module.cpp", "renameme.cpp"]:
        with open(f"{TEMPLATEDIR}/{src_filename}", "r") as inf:
            sourcecode = inf.read()

        sourcecode = sourcecode.replace("package", PACKAGE.lower())
        
        with open(f"{REPODIR}/pybindsrc/{src_filename}", "w") as outf:
            outf.write(sourcecode)

if args.daq_modules:

    for pkg in ["appfwk", "opmonlib"]:
        find_package_calls.append(f"find_package({pkg} REQUIRED)")

    make_package_dir(f"{REPODIR}/src")
    make_package_dir(f"{REPODIR}/plugins")
    make_package_dir(f"{REPODIR}/schema/{PACKAGE}")

    for module in args.daq_modules:
        if not re.search(r"^[A-Z][^_]+", module):
            cleanup(REPODIR)
            error(f"""
Requested module name \"{module}\" needs to be in PascalCase. 
Please see https://dune-daq-sw.readthedocs.io/en/latest/packages/styleguide/ 
for more on naming conventions. Exiting...
""")

        daq_add_plugin_calls.append(f"daq_add_plugin({module} duneDAQModule LINK_LIBRARIES appfwk::appfwk) # Replace appfwk library with a more specific library when appropriate")
        daq_codegen_calls.append(f"daq_codegen({module.lower()}.jsonnet TEMPLATES Structs.hpp.j2 Nljs.hpp.j2)") 
        daq_codegen_calls.append(f"daq_codegen({module.lower()}info.jsonnet DEP_PKGS opmonlib TEMPLATES opmonlib/InfoStructs.hpp.j2 opmonlib/InfoNljs.hpp.j2)")

        for src_filename in ["RenameMe.hpp", "RenameMe.cpp", "renameme.jsonnet", "renamemeinfo.jsonnet"]:

            if pathlib.Path(src_filename).suffix in [".hpp", ".cpp"]:
                DEST_FILENAME = src_filename.replace("RenameMe", module)
                DEST_FILENAME = f"{REPODIR}/plugins/{DEST_FILENAME}"
            elif pathlib.Path(src_filename).suffix in [".jsonnet"]:
                DEST_FILENAME = src_filename.replace("renameme", module.lower())
                DEST_FILENAME = f"{REPODIR}/schema/{PACKAGE}/{DEST_FILENAME}"
            else:
                assert False, "SCRIPT ERROR: unhandled filename"

            shutil.copyfile(f"{TEMPLATEDIR}/{src_filename}", DEST_FILENAME)

            with open(f"{TEMPLATEDIR}/{src_filename}", "r") as inf:
                sourcecode = inf.read()
                    
            sourcecode = sourcecode.replace("RenameMe", module)

            # Handle the header guards
            sourcecode = sourcecode.replace("PACKAGE", PACKAGE.upper())
            sourcecode = sourcecode.replace("RENAMEME", module.upper())

            # Handle namespace
            sourcecode = sourcecode.replace("package", PACKAGE.lower())

            # And schema files
            sourcecode = sourcecode.replace("renameme", module.lower())

            with open(DEST_FILENAME, "w") as outf:
                outf.write(sourcecode)

if args.user_apps:
    make_package_dir(f"{REPODIR}/apps")

    for user_app in args.user_apps:
        if re.search(r"[A-Z]", user_app):
            cleanup(REPODIR)
            error(f"""
Requested user application name \"{user_app}\" needs to be in snake_case. 
Please see https://dune-daq-sw.readthedocs.io/en/latest/packages/styleguide/ 
for more on naming conventions. Exiting...
""")
        DEST_FILENAME = f"{REPODIR}/apps/{user_app}.cxx"
        with open(f"{TEMPLATEDIR}/renameme.cxx") as inf:
            sourcecode = inf.read()

        sourcecode = sourcecode.replace("renameme", user_app)

        with open(DEST_FILENAME, "w") as outf:
            outf.write(sourcecode)

        daq_add_application_calls.append(f"daq_add_application({user_app} {user_app}.cxx LINK_LIBRARIES ) # Any libraries to link in not yet determined")
    

if args.test_apps:
    make_package_dir(f"{REPODIR}/test/apps")

    for test_app in args.test_apps:
        if re.search(r"[A-Z]", test_app):
            cleanup(REPODIR)
            error(f"""
Requested test application name \"{test_app}\" needs to be in snake_case. 
Please see https://dune-daq-sw.readthedocs.io/en/latest/packages/styleguide/ 
for more on naming conventions. Exiting...
""")
        DEST_FILENAME = f"{REPODIR}/test/apps/{test_app}.cxx"
        with open(f"{TEMPLATEDIR}/renameme.cxx") as inf:
            sourcecode = inf.read()
    
        sourcecode = sourcecode.replace("renameme", test_app)

        with open(DEST_FILENAME, "w") as outf:
            outf.write(sourcecode)

        daq_add_application_calls.append(f"daq_add_application({test_app} {test_app}.cxx TEST LINK_LIBRARIES ) # Any libraries to link in not yet determined")

make_package_dir(f"{REPODIR}/unittest")
shutil.copyfile(f"{TEMPLATEDIR}/Placeholder_test.cxx", f"{REPODIR}/unittest/Placeholder_test.cxx")
daq_add_unit_test_calls.append("daq_add_unit_test(Placeholder_test LINK_LIBRARIES)  # Any libraries to link in not yet determined")
find_package_calls.append("find_package(Boost COMPONENTS unit_test_framework REQUIRED)")

make_package_dir(f"{REPODIR}/docs")
if not os.path.exists(f"{REPODIR}/README.md") and not os.path.exists(f"{REPODIR}/docs/README.md"):
    with open(f"{REPODIR}/docs/README.md", "w") as outf:
        GENERATION_TIME = get_time("as_date")
        outf.write(f"# No Official User Documentation Has Been Written Yet ({GENERATION_TIME})\n")
elif os.path.exists(f"{REPODIR}/README.md"):  # i.e., README.md isn't (yet) in the docs/ subdirectory
    os.chdir(REPODIR)
    proc = subprocess.Popen(f"git mv README.md docs/README.md", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    proc.communicate()
    RETVAL = proc.returncode
    if RETVAL != 0:
        cleanup(REPODIR)
        error(f"There was a problem attempting a git mv of README.md to docs/README.md in {REPODIR}; exiting...")

make_package_dir(f"{REPODIR}/cmake")
config_template_html=f"https://raw.githubusercontent.com/DUNE-DAQ/daq-cmake/dunedaq-v2.6.0/configs/Config.cmake.in"
proc = subprocess.Popen(f"curl -o {REPODIR}/cmake/{PACKAGE}Config.cmake.in -O {config_template_html}", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
proc.communicate()
RETVAL = proc.returncode

if RETVAL != 0:
    cleanup(REPODIR)
    error(f"There was a problem trying to pull down {config_template_html} from the web; exiting...")

def print_cmakelists_section(list_of_calls, section_of_webpage = None):
    for i, line in enumerate(list_of_calls):
        if i == 0 and section_of_webpage is not None:
            cmakelists.write(f"\n# See https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-cmake/#{section_of_webpage}\n") 
        cmakelists.write("\n" + line)

    if len(list_of_calls) > 0:
        cmakelists.write("""

##############################################################################

""")

with open("CMakeLists.txt", "w") as cmakelists:
    GENERATION_TIME = get_time("as_date")
    cmakelists.write(f"""

# This is a skeleton CMakeLists.txt file, auto-generated on
# {GENERATION_TIME}.  The developer(s) of this package should delete
# this comment as well as adding dependent targets, packages,
# etc. specific to the package. For details on how to write a package,
# please see
# https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-cmake/

cmake_minimum_required(VERSION 3.12)
project({PACKAGE} VERSION 0.0.0)

find_package(daq-cmake REQUIRED)

daq_setup_environment()

""")

    print_cmakelists_section(find_package_calls)
    print_cmakelists_section(daq_codegen_calls, "daq_codegen")
    print_cmakelists_section(daq_add_library_calls, "daq_add_library")
    print_cmakelists_section(daq_add_python_bindings_calls, "daq_add_python_bindings")
    print_cmakelists_section(daq_add_plugin_calls, "daq_add_plugin")
    print_cmakelists_section(daq_add_application_calls, "daq_add_application")
    print_cmakelists_section(daq_add_unit_test_calls, "daq_add_unit_test")

    cmakelists.write("daq_install()\n\n")

os.chdir(REPODIR)

# Only need .gitkeep if the directory is otherwise empty
for filename, ignored, ignored in os.walk(REPODIR):
    if os.path.isdir(filename) and os.listdir(filename) != [".gitkeep"]:
        if os.path.exists(f"{filename}/.gitkeep"):
            os.unlink(f"{filename}/.gitkeep")

proc = subprocess.Popen("git add -A", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
proc.communicate()
RETVAL = proc.returncode

if RETVAL != 0:
    error(f"""
There was a problem trying to "git add" the newly-created files and directories in {REPODIR}; exiting...
""")

COMMAND=" ".join(sys.argv)
proc = subprocess.Popen(f"git commit -m \"This {os.path.basename (__file__)}-generated boilerplate for the {PACKAGE} package was created by this command: {COMMAND}\"", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
proc.communicate()
RETVAL = proc.returncode

if RETVAL != 0:
    error(f"""
There was a problem trying to auto-generate the commit off the newly auto-generated files in {REPODIR}. Exiting...
""")

print(f"""
This script has created the boilerplate for your new package in
{REPODIR}. 
Note that the code has been committed *locally*; please review it before you 
push it to the central repo and start making your own edits. 

For details on how to write a DUNE DAQ package, please look at the 
official daq-cmake documentation at 
https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-cmake/
""")