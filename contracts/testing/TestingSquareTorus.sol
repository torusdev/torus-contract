// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "../../libraries/SquareTorus.sol";

contract TestingSquareTorus {
    function sqrt(uint256 input, SquareTorus.Precision precision) external pure returns (uint256) {
        return SquareTorus.sqrt(input, 10**18, precision);
    }
}
