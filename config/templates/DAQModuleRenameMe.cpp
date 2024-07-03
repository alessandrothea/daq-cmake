/**
 * @file RenameMe.cpp
 *
 * Implementations of RenameMe's functions
 *
 * This is part of the DUNE DAQ Software Suite, copyright 2020.
 * Licensing/copyright details are in the COPYING file that you should have
 * received with this code.
 */

#include "RenameMe.hpp"

#include "package/renameme/Nljs.hpp"
#include "package/renamemeinfo/InfoNljs.hpp"

#include <string>

namespace dunedaq::package {

RenameMe::RenameMe(const std::string& name)
  : dunedaq::appfwk::DAQModule(name)
{
  register_command("conf", &RenameMe::do_conf);
}

void
RenameMe::init(std::shared_ptr<appfwk::ModuleConfiguration> /* mcfg */)
{}

void
RenameMe::get_info(opmonlib::InfoCollector& ci, int /* level */)
{
  renamemeinfo::Info info;
  info.total_amount = m_total_amount;
  info.amount_since_last_get_info_call = m_amount_since_last_get_info_call.exchange(0);

  ci.add(info);
}

void
RenameMe::do_conf(const data_t& /* do not pass an argument*/ )
{
}

} // namespace dunedaq::package

DEFINE_DUNE_DAQ_MODULE(dunedaq::package::RenameMe)
