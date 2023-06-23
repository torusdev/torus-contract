// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

interface ICurveAddressProvider {
    function get_registry() external view returns (address);
}
