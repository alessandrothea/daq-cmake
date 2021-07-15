/**
 * @file toy_wrapper.cpp Example Pybind11 source file for wrapping a dunedaq library
 *
 * This is part of the DUNE DAQ Application Framework, copyright 2020.
 * Licensing/copyright details are in the COPYING file that you should have
 * received with this code.
 */

#include "toylibrary/IntPrinter.hpp"
#include "toylibrary/ValueWrapper.hpp"

#include "logging/Logging.hpp"

#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include <sstream>
#include <string>
#include <vector>

namespace py = pybind11;

namespace dunedaq {
namespace toylibrary {

// Toy functions for pybind11 demo
int
WindUp(int number)
{
  return ++number; // NOLINT(runtime/increment_decrement)
}

int
WindDown(int number)
{
  return --number; // NOLINT(runtime/increment_decrement)
}

void
PlayInts(const std::vector<int>& numbers, bool new_line = false)
{
  std::string separator = new_line ? "\n" : ",";
  std::stringstream numbers_stream;
  for (uint i = 0; i < numbers.size(); ++i) {
    if (i)
      numbers_stream << separator;
    numbers_stream << numbers.at(i);
  }
  TLOG() << numbers_stream.str() << std::endl; // NOLINT
}

namespace python {

// The name of the top level python module supplied here (via the first argument of PYBIND11_MODULE()) must match the
// file name of the compiled .so file. With daq_add_python_bindings(), the shared object is named
// "_daq_${PROJECT_NAME}_py.so".
PYBIND11_MODULE(_daq_toylibrary_py, top_module)
{

  top_module.doc() = "Python module wrapper for C++ library, toylibrary"; // optional module docstring

  // expose toylibrary classes in the top level python module

  py::class_<toylibrary::ValueWrapper<int>>(top_module, "ValueWrapperInt")

    // Expose ValueWrapper<int> constructor
    .def(py::init<const int&>())

    // expose the ValueWrapper<int> method GetValue
    .def("GetValue", &toylibrary::ValueWrapper<int>::GetValue);

  py::class_<toylibrary::IntPrinter>(top_module, "IntPrinter")

    // Expose IntPrinter constructor
    .def(py::init<const ValueWrapper<int>&>())

    // expose the IntPrinter method Show
    .def("Show", &toylibrary::IntPrinter::Show);

  // Sub-module of the top module
  py::module_ wind_module = top_module.def_submodule("wind");

  // Expose "winding" functions via wind sub-module
  wind_module.def("WindUp", &toylibrary::WindUp);
  wind_module.def("WindDown", &toylibrary::WindDown);

  // Another sub-module of top module above
  py::module_ play_module = top_module.def_submodule("play");

  // Expose "playing" functions via the play sub-module
  // Here we are adding argument names, as well as defining a default value for one of the function arguments. The
  // function can be called from python with or without that argument.
  play_module.def("PlayInts", &toylibrary::PlayInts, py::arg("numbers"), py::arg("new_line") = false);
}

} // namespace python
} // namespace toylibrary
} // namespace dunedaq
