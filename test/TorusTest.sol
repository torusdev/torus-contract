// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

// import "forge-std/Test.sol";
import "../lib/forge-std/src/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../contracts/Controller.sol";
import "../contracts/TorusPool.sol";
import "../contracts/CurveHandler.sol";
import "../contracts/ConvexHandler.sol";
import "../contracts/CurveRegistryCache.sol";
import "../contracts/tokenomics/InflationManager.sol";
import "../contracts/tokenomics/TORUSLockerV2.sol";
import "../contracts/tokenomics/TORUSToken.sol";
import "../contracts/tokenomics/LpTokenStaker.sol";
import "../contracts/tokenomics/EmergencyMinter.sol";
import "../contracts/tokenomics/TORUSMintingRebalancingRewardsHandler.sol";
import "../contracts/oracles/GenericOracle.sol";
import "../contracts/oracles/CurveLPOracle.sol";
import "../contracts/oracles/ChainlinkOracle.sol";
import "../contracts/testing/MockErc20.sol";

library CurvePools {
    address internal constant TRI_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant STETH_ETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address internal constant RETH_ETH_POOL = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
    address internal constant FRAX_3CRV = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    address internal constant REN_BTC = 0x93054188d876f558f4a66B2EF1d97d16eDf0895B;
    address internal constant BBTC = 0x071c661B4DeefB59E2a3DdB20Db036821eeE8F4b;
    address internal constant MIM_3CRV = 0x5a6A4D54456819380173272A5E8E9B9904BdF41B;
    address internal constant TORUS_ETH = 0x838af967537350D2C44ABB8c010E49E32673ab94;
    address internal constant FRAX_BP = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;
    address internal constant GUSD_FRAX_BP = 0x4e43151b78b5fbb16298C1161fcbF7531d5F8D93;
    address internal constant EURT_3CRV = 0x9838eCcC42659FA8AA7daF2aD134b53984c9427b;
    address internal constant BUSD_FRAX_BP = 0x8fdb0bB9365a46B145Db80D0B1C5C5e979C84190;
    address internal constant SUSD_DAI_USDT_USDC = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;
}

library Tokens {
    address internal constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address internal constant WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address internal constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address internal constant TRI_CRV = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address internal constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant USDT = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address internal constant CRV = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address internal constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant ST_ETH = address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address internal constant R_ETH = address(0xae78736Cd615f374D3085123A210448E74Fc6393);
    address internal constant CVX = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address internal constant SETH = address(0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb);
    address internal constant TRI_POOL_LP = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address internal constant STETH_ETH_LP = address(0x06325440D014e39736583c165C2963BA99fAf14E);
    address internal constant MIM_3CRV_LP = address(0x5a6A4D54456819380173272A5E8E9B9904BdF41B);
    address internal constant BBTC_LP = address(0x410e3E86ef427e30B9235497143881f717d93c2A);
    address internal constant MIM_UST_LP = address(0x55A8a39bc9694714E2874c1ce77aa1E599461E18);
    address internal constant FRAX_3CRV_LP = address(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);
    address internal constant TORUS = address(0x9aE380F0272E2162340a5bB646c354271c0F5cFC);
    address internal constant EURT_3CRV_LP = address(0x3b6831c0077a1e44ED0a21841C3bC4dC11bCE833);
    address internal constant FRAX = address(0x853d955aCEf822Db058eb8505911ED77F175b99e);
}

contract TorusTest is Test {
    using stdJson for string;
    using stdStorage for StdStorage;

    address constant MINTER_ADDRESS = 0xeC037423A61B634BFc490dcc215236349999ca3d;
    address constant TORUS_ADDRESS = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    address constant MULTISIG_ADDRESS = 0xB27DC5f8286f063F11491c8f349053cB37718bea;

    bytes32 constant LOCKER_V2_MERKLE_TORUS =
        0x1fb27a93b1597fb63a71400761fa335d34875bc82ed5d1e2182cbb0a966049a7;

    address public bb8 = makeAddr("bb8");
    address public r2 = makeAddr("r2");
    address public c3po = makeAddr("c3po");

    uint256 internal mainnetFork;

    bool internal _isFork;

    function setUp() public virtual {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

        mainnetFork = vm.createFork(MAINNET_RPC_URL, 17389623);
    }

    function _setFork(uint256 forkId) internal {
        _isFork = true;
        vm.selectFork(forkId);
    }

    function _getTORUSToken() internal returns (TORUSToken) {
        if (_isFork) {
            return TORUSToken(TORUS_ADDRESS);
        }
        return new TORUSToken();
    }

    function _createRegistryCache() internal returns (CurveRegistryCache) {
        CurveRegistryCache registryCache = new CurveRegistryCache();
        if (_isFork) {
            registryCache.initPool(CurvePools.STETH_ETH_POOL);
//            registryCache.initPool(CurvePools.RETH_ETH_POOL);
            registryCache.initPool(CurvePools.FRAX_3CRV);
            registryCache.initPool(CurvePools.TRI_POOL);
            registryCache.initPool(CurvePools.REN_BTC);
            registryCache.initPool(CurvePools.MIM_3CRV);
            registryCache.initPool(CurvePools.FRAX_BP);
            registryCache.initPool(CurvePools.EURT_3CRV);
            registryCache.initPool(CurvePools.BUSD_FRAX_BP);
            registryCache.initPool(CurvePools.SUSD_DAI_USDT_USDC);
            registryCache.initPool(CurvePools.TORUS_ETH);
        }
        return registryCache;
    }

    function _createController(TORUSToken torus, CurveRegistryCache registryCache)
        internal
        returns (Controller)
    {
        Controller controller = new Controller(address(torus), address(registryCache));
        address emergencyMinter = address(controller.emergencyMinter());
        if (_isFork) {
            vm.prank(MINTER_ADDRESS);
        }
        torus.addMinter(emergencyMinter);
        return controller;
    }

    function _createAndInitializeController() internal returns (Controller) {
        TORUSToken torus = _getTORUSToken();
        Controller controller = _createController(torus, _createRegistryCache());
        controller.setConvexHandler(address(new ConvexHandler(address(controller))));
        controller.setCurveHandler(address(new CurveHandler(address(controller))));
        InflationManager inflationManager = _createInflationManager(controller);
        _createLpTokenStaker(inflationManager, torus);
        GenericOracle genericOracle = _createGenericOracle();
        _createCurveLpOracle(controller, genericOracle);
        controller.setPriceOracle(address(genericOracle));
        return controller;
    }

    function _createCurveLpOracle(Controller controller, GenericOracle genericOracle)
        internal
        returns (CurveLPOracle)
    {
        CurveLPOracle curveLPOracle = new CurveLPOracle(
            address(genericOracle),
            address(controller)
        );
        ChainlinkOracle chainlinkOracle = new ChainlinkOracle();
        genericOracle.initialize(address(curveLPOracle), address(chainlinkOracle));
        return curveLPOracle;
    }

    function _createInflationManager(Controller controller) internal returns (InflationManager) {
        InflationManager inflationManager = new InflationManager(address(controller));
        controller.setInflationManager(address(inflationManager));
        return inflationManager;
    }

    function _createRebalancingRewardsHandler(Controller controller)
        internal
        returns (TORUSMintingRebalancingRewardsHandler)
    {
        TORUSToken torus = TORUSToken(controller.torusToken());
        TORUSMintingRebalancingRewardsHandler rebalancingRewardsHandler = new TORUSMintingRebalancingRewardsHandler(
                controller,
                torus,
                controller.emergencyMinter()
            );

        if (_isFork) {
            vm.prank(MINTER_ADDRESS);
        }
        torus.addMinter(address(rebalancingRewardsHandler));
        return rebalancingRewardsHandler;
    }

    function _createLpTokenStaker(InflationManager inflationManager, TORUSToken torus)
        internal
        returns (LpTokenStaker)
    {
        IController controller = inflationManager.controller();
        LpTokenStaker lpTokenStaker = new LpTokenStaker(
            address(controller),
            torus,
            controller.emergencyMinter()
        );

        if (_isFork) {
            vm.prank(MINTER_ADDRESS);
        }
        torus.addMinter(address(lpTokenStaker));
        controller.setLpTokenStaker(address(lpTokenStaker));
        return lpTokenStaker;
    }

    function _createLockerV2(Controller controller) internal returns (TORUSLockerV2) {
        address crv = Tokens.CRV;
        address cvx = Tokens.CVX;
        if (!_isFork) {
            crv = address(new MockErc20(18));
            cvx = address(new MockErc20(18));
        }
        TORUSLockerV2 locker = new TORUSLockerV2(
            address(controller),
            controller.torusToken(),
            MULTISIG_ADDRESS,
            crv,
            cvx
        );
        return locker;
    }

    function _createGenericOracle() internal returns (GenericOracle) {
        return new GenericOracle();
    }

    function _createTorusPool(
        Controller controller,
        TORUSMintingRebalancingRewardsHandler rebalancingRewardsHandler,
        TORUSLockerV2 locker,
        address underlying,
        string memory name,
        string memory symbol
    ) internal returns (TorusPool) {
        TorusPool pool = new TorusPool(
            underlying,
            address(controller),
            address(locker),
            name,
            symbol,
            Tokens.CVX,
            Tokens.CRV
        );
        controller.addPool(address(pool));
        controller.inflationManager().addPoolRebalancingRewardHandler(
            address(pool),
            address(rebalancingRewardsHandler)
        );
        controller.inflationManager().updatePoolWeights();
        return pool;
    }

    function setTokenBalance(
        address who,
        address token,
        uint256 amt
    ) internal {
        // tranfer weth from whale
        if (token == 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) {
            // alternative solution for stETH as proxy slot issue on foundry
            vm.prank(0x176F3DAb24a159341c0509bB36B833E7fdd0a132);
            IERC20(token).transfer(who, amt);
        } else if (token == Tokens.ETH) {
            vm.prank(Tokens.ETH);
            (bool sent, bytes memory data) = who.call{value: 100 ether}("");
            require(sent, "eth sent failed");
        } else if (token == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) {
            vm.prank(Tokens.ETH);
            (bool sent, bytes memory data) = who.call{value: amt}("");
            vm.prank(who);
            IWETH(token).deposit{value: amt}();
//            bytes4 sel = IERC20(token).balanceOf.selector;
//            stdstore.target(token).sig(sel).with_key(who).checked_write(amt);
        }
    }
}
