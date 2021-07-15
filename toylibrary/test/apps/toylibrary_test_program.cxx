/**
 *
 * @file toylibrary_test_app.cxx
 *
 * A basic example integration test program. It demonstrates how
 * developers can use Boost's program_options library to handle
 * arguments passed to their application, as well as how they can use
 * the ERS library to define exceptions.
 *
 * Run "toylibrary_test_app --help" to see options
 *
 * This is part of the DUNE DAQ Application Framework, copyright 2020.
 * Licensing/copyright details are in the COPYING file that you should have
 * received with this code.
 */

#include "toylibrary/IntPrinter.hpp"

#include "logging/Logging.hpp"

#include <boost/program_options.hpp>
#include <string>

namespace bpo = boost::program_options;

namespace dunedaq {
ERS_DECLARE_ISSUE(toylibrary,           ///< Namespace
                  ParameterDomainIssue, ///< Issue class name
                  "ParameterDomainIssue: \"" << ers_messg << "\"",
                  ((std::string)ers_messg))
} // namespace dunedaq

namespace {

int number_to_print = 7;
int times_to_print_number = 3;

} // namespace ""

int
main(int argc, char* argv[])
{

  std::ostringstream descstr;
  descstr << argv[0] << " known arguments ";

  std::ostringstream number_to_print_desc;
  number_to_print_desc << "Number you want to print to the screen (default is " << number_to_print << ")";

  std::ostringstream times_to_print_number_desc;
  times_to_print_number_desc << "Times you want to print the number (default is " << times_to_print_number << ")";

  bpo::options_description desc(descstr.str());
  desc.add_options()("number_to_print", bpo::value<int>(), number_to_print_desc.str().c_str())(
    "times_to_print_number", bpo::value<int>(), times_to_print_number_desc.str().c_str())("help,h",
                                                                                          "produce help message");

  bpo::variables_map vm;
  bpo::store(bpo::parse_command_line(argc, argv, desc), vm);
  bpo::notify(vm);

  if (vm.count("help")) {
    TLOG() << desc << std::endl;
    return 0;
  }

  if (vm.count("number_to_print")) {
    number_to_print = vm["number_to_print"].as<int>();
  }

  if (vm.count("times_to_print_number")) {
    times_to_print_number = vm["times_to_print_number"].as<int>();

    if (times_to_print_number < 0) {
      throw dunedaq::toylibrary::ParameterDomainIssue(ERS_HERE, "# of times to print number must be 0 or greater");
    }
  }

  dunedaq::toylibrary::ValueWrapper<int> wrapped_number_to_print(number_to_print);
  dunedaq::toylibrary::IntPrinter intprinter_instance(wrapped_number_to_print);

  for (int i_t = 0; i_t < times_to_print_number; ++i_t) {
    intprinter_instance.Show();
  }

  return 0;
}
