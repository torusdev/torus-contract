pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../contracts/Controller.sol";
import "../contracts/tokenomics/TORUSToken.sol";
import "../contracts/CurveRegistryCache.sol";
import "../contracts/ConvexHandler.sol";
import "../contracts/CurveHandler.sol";
import "../contracts/tokenomics/InflationManager.sol";
import "../contracts/oracles/GenericOracle.sol";
import "../contracts/tokenomics/LpTokenStaker.sol";
import "../contracts/tokenomics/TORUSMintingRebalancingRewardsHandler.sol";
import "../contracts/tokenomics/TORUSLockerV2.sol";
import "../contracts/TorusPool.sol";
import "../contracts/oracles/CurveLPOracle.sol";
import "../contracts/oracles/ChainlinkOracle.sol";

contract Deploy is Test {
    Controller public controller;
    IInflationManager public inflationManager;
    ILpTokenStaker public lpTokenStaker;
    ITORUSToken public torus;
    TORUSMintingRebalancingRewardsHandler public rewardsHandler;
    TORUSLockerV2 public locker;
    TorusPool public torusPool;
    IERC20Metadata public underlying;
    uint256 public decimals = 18;
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    function run() external {
        vm.startBroadcast(deployerPrivateKey);
        _initializeContracts();
        underlying = IERC20Metadata(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
        torusPool = _createTorusPool(
            controller,
            rewardsHandler,
            locker,
            address(underlying),
            "Torus ETH",
            "torusETH"
        );
        torusPool.addCurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022); // add steth_eth pool
        torusPool.addCurvePool(0x0f3159811670c117c372428D4E69AC32325e4D0F); // add reth_eth pool

        ITorusPool.PoolWeight[] memory weights = new ITorusPool.PoolWeight[](2);
        weights[0] = ITorusPool.PoolWeight(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, 0.6e18);
        weights[1] = ITorusPool.PoolWeight(0x0f3159811670c117c372428D4E69AC32325e4D0F, 0.4e18);
        _setWeights(address(torusPool), weights);

        // only for testing purpose
        _necessaryForTesting();
        vm.stopBroadcast();
    }

    function _necessaryForTesting() internal {
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).deposit{value: 100 * 10**decimals}();
        underlying.approve(address(torusPool), 100 * 10**decimals);
        torusPool.deposit(100 * 10**decimals, 1);
    }

    function _initializeContracts() internal {
        controller = _createAndInitializeController();
        inflationManager = controller.inflationManager();
        lpTokenStaker = controller.lpTokenStaker();
        torus = ITORUSToken(controller.torusToken());
        rewardsHandler = _createRebalancingRewardsHandler(controller);
        locker = _createLockerV2(controller);
    }

    function _createAndInitializeController() internal returns (Controller) {
        TORUSToken torus = new TORUSToken();
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

    function _createRegistryCache() internal returns (CurveRegistryCache) {
        CurveRegistryCache registryCache = new CurveRegistryCache();
        registryCache.initPool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022); // steth_eth pool
        registryCache.initPool(0x0f3159811670c117c372428D4E69AC32325e4D0F); // reth_eth pool
        return registryCache;
    }

    function _createInflationManager(Controller controller) internal returns (InflationManager) {
        InflationManager inflationManager = new InflationManager(address(controller));
        controller.setInflationManager(address(inflationManager));
        return inflationManager;
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

        torus.addMinter(address(lpTokenStaker));
        controller.setLpTokenStaker(address(lpTokenStaker));
        return lpTokenStaker;
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
            0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, // cvx
            0xD533a949740bb3306d119CC777fa900bA034cd52 // crv
        );
        controller.addPool(address(pool));
        controller.inflationManager().addPoolRebalancingRewardHandler(
            address(pool),
            address(rebalancingRewardsHandler)
        );
        controller.inflationManager().updatePoolWeights();
        return pool;
    }

    function _createController(TORUSToken torus, CurveRegistryCache registryCache)
    internal
    returns (Controller)
    {
        Controller controller = new Controller(address(torus), address(registryCache));
        address emergencyMinter = address(controller.emergencyMinter());
        torus.addMinter(emergencyMinter);
        return controller;
    }

    function _setWeights(address pool, ITorusPool.PoolWeight[] memory weights) internal {
        IController.WeightUpdate memory weightUpdate = IController.WeightUpdate({
            torusPoolAddress: pool,
            weights: weights
        });
        controller.updateWeights(weightUpdate);
    }

    function _createLockerV2(Controller controller) internal returns (TORUSLockerV2) {
        address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

        TORUSLockerV2 locker = new TORUSLockerV2(
            address(controller),
            controller.torusToken(),
            address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            crv,
            cvx
        );
        return locker;
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

    function _createGenericOracle() internal returns (GenericOracle) {
        return new GenericOracle();
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

        torus.addMinter(address(rebalancingRewardsHandler));
        return rebalancingRewardsHandler;
    }
}