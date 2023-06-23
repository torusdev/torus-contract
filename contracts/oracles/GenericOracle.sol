// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IOracle.sol";

contract GenericOracle is IOracle, Ownable {
    event CustomOracleAdded(address token, address oracle);

    mapping(address => IOracle) public customOracles;

    IOracle internal _chainlinkOracle;
    IOracle internal _curveLpOracle;
    address internal WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant _ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function initialize(address curveLpOracle, address chainlinkOracle) external {
        require(address(_curveLpOracle) == address(0), "already initialized");
        _chainlinkOracle = IOracle(chainlinkOracle);
        _curveLpOracle = IOracle(curveLpOracle);
    }

    function isTokenSupported(address token) external view override returns (bool) {
        token = token == WETH ? _ETH_ADDRESS : token;
        return
            address(customOracles[token]) != address(0) ||
            _chainlinkOracle.isTokenSupported(token) ||
            _curveLpOracle.isTokenSupported(token);
    }

    function getUSDPrice(address token) external view virtual returns (uint256) {
        if (token == WETH)
            token = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        if (_chainlinkOracle.isTokenSupported(token)) {
            return _chainlinkOracle.getUSDPrice(token);
        }
        if (address(customOracles[token]) != address(0)) {
            return customOracles[token].getUSDPrice(token);
        }
        return _curveLpOracle.getUSDPrice(token);
    }

    function setCustomOracle(address token, address oracle) external onlyOwner {
        customOracles[token] = IOracle(oracle);
        emit CustomOracleAdded(token, oracle);
    }
}
