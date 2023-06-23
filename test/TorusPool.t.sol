// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "./TorusPoolBaseTest.sol";
import "../interfaces/vendor/IBooster.sol";

contract TorusPoolTest is TorusPoolBaseTest {
    TorusPool public torusPool;
    IERC20Metadata public underlying;
    uint256 public decimals = 18;

    function setUp() public override {
        super.setUp();
        // Pool accepts only WETH for convenience
        underlying = IERC20Metadata(Tokens.WETH);
//        decimals = underlying.decimals();
        setTokenBalance(bb8, address(underlying), 100 * 10**18);
        torusPool = _createTorusPool(
            controller,
            rewardsHandler,
            locker,
            address(underlying),
            "Torus DAI",
            "torusDAI"
        );

        torusPool.addCurvePool(CurvePools.STETH_ETH_POOL);
//        torusPool.addCurvePool(CurvePools.TRI_POOL);

        ITorusPool.PoolWeight[] memory weights = new ITorusPool.PoolWeight[](1);
        weights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 1e18);
//        weights[1] = ITorusPool.PoolWeight(CurvePools.TRI_POOL, 0.4e18);
        _setWeights(address(torusPool), weights);
    }
//
    function testInitialState() public {
        assertEq(address(torusPool.controller()), address(controller));
        assertEq(torusPool.lpToken().name(), "Torus DAI");
        assertEq(torusPool.lpToken().symbol(), "torusDAI");
        assertEq(address(torusPool.underlying()), address(underlying));
        assertFalse(torusPool.isShutdown());
        assertFalse(torusPool.rebalancingRewardActive());
        assertEq(torusPool.depegThreshold(), 0.03e18);
        assertEq(torusPool.maxIdleCurveLpRatio(), 0.05e18);
    }

    function testDepositWithoutStaking() public {
        vm.startPrank(bb8);
//        Enable it for ERC20
//        underlying.approve(address(torusPool), 100_000 * 10**decimals);

        uint256 balanceBefore = torusPool.lpToken().balanceOf(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);
        torusPool.deposit(100 * 10**decimals, 1, false);
        uint256 lpReceived = torusPool.lpToken().balanceOf(bb8) - balanceBefore;
        assertApproxEqRel(100 * 10**decimals, lpReceived, 0.01e18);

        _checkAllocations();
    }

    function testDepositAndStake() public {
        vm.startPrank(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);

        torusPool.deposit(100 * 10**decimals, 1);
        uint256 lpReceived = controller.lpTokenStaker().getUserBalanceForPool(
            address(torusPool),
            bb8
        );
        assertApproxEqRel(100 * 10**decimals, lpReceived, 0.01e18);
        _checkAllocations();
    }

    function testWidthrawWithoutStaking() public {
        vm.startPrank(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);

        torusPool.deposit(100 * 10**decimals, 1, false);
        uint256 balanceBeforeWithdraw = underlying.balanceOf(bb8);
        uint256 lpBalanceBeforeWithdraw = torusPool.lpToken().balanceOf(bb8);
        torusPool.withdraw(50 * 10**decimals, 1);
        uint256 lpDiff = lpBalanceBeforeWithdraw - torusPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(50 * 10**decimals, lpDiff, 0.01e18);
        uint256 underlyingReceived = underlying.balanceOf(bb8) - balanceBeforeWithdraw;
        assertApproxEqRel(50 * 10**decimals, underlyingReceived, 0.01e18);
        _checkAllocations();
    }

    function testWidthrawWithStaking() public {
        vm.startPrank(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);

        torusPool.deposit(100 * 10**decimals, 1);
        uint256 balanceBeforeWithdraw = underlying.balanceOf(bb8);
        uint256 lpBalanceBeforeWithdraw = controller.lpTokenStaker().getUserBalanceForPool(
            address(torusPool),
            bb8
        );
        torusPool.unstakeAndWithdraw(50 * 10**decimals, 1);
        uint256 lpDiff = lpBalanceBeforeWithdraw -
            controller.lpTokenStaker().getUserBalanceForPool(address(torusPool), bb8);
        assertApproxEqRel(50 * 10**decimals, lpDiff, 0.01e18);
        uint256 underlyingReceived = underlying.balanceOf(bb8) - balanceBeforeWithdraw;
        assertApproxEqRel(50 * 10**decimals, underlyingReceived, 0.01e18);
        _checkAllocations();
    }

    function testWithdrawWithV0Pool() public {
        torusPool.addCurvePool(CurvePools.RETH_ETH_POOL);
        ITorusPool.PoolWeight[] memory newWeights = new ITorusPool.PoolWeight[](2);
        newWeights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 0.6e18);
        newWeights[1] = ITorusPool.PoolWeight(CurvePools.RETH_ETH_POOL, 0.4e18);
        skip(14 days);
        _setWeights(address(torusPool), newWeights);

        vm.startPrank(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);
        torusPool.deposit(100 * 10**decimals, 1);
        uint256 balanceBeforeWithdraw = underlying.balanceOf(bb8);
        uint256 lpBalanceBeforeWithdraw = controller.lpTokenStaker().getUserBalanceForPool(
            address(torusPool),
            bb8
        );
        torusPool.unstakeAndWithdraw(50 * 10**decimals, 1);
        uint256 lpDiff = lpBalanceBeforeWithdraw -
            controller.lpTokenStaker().getUserBalanceForPool(address(torusPool), bb8);
        assertApproxEqRel(50 * 10**decimals, lpDiff, 0.1e18);
        uint256 underlyingReceived = underlying.balanceOf(bb8) - balanceBeforeWithdraw;
        assertApproxEqRel(30 * 10**decimals, underlyingReceived, 0.1e18);
    }

    function testRebalance() public {
        vm.startPrank(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);

        torusPool.deposit(50 * 10**decimals, 1);
        vm.stopPrank();

        skip(14 days);
        torusPool.addCurvePool(CurvePools.RETH_ETH_POOL);

        ITorusPool.PoolWeight[] memory newWeights = new ITorusPool.PoolWeight[](2);
        newWeights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 0.6e18);
        newWeights[1] = ITorusPool.PoolWeight(CurvePools.RETH_ETH_POOL, 0.4e18);
        _setWeights(address(torusPool), newWeights);

        skip(1 hours);

        assertTrue(torusPool.rebalancingRewardActive());

        uint256 deviationBefore = torusPool.computeTotalDeviation();
        uint256 torusBalanceBefore = IERC20(controller.torusToken()).balanceOf(bb8);
        vm.prank(bb8);
        torusPool.deposit(50 * 10**decimals, 1);
        uint256 deviationAfter = torusPool.computeTotalDeviation();
        assertLt(deviationAfter, deviationBefore);
        uint256 torusBalanceAfter = IERC20(controller.torusToken()).balanceOf(bb8);
        assertGt(torusBalanceAfter, torusBalanceBefore);
    }

    function testClaimRewards() public {
        vm.startPrank(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);
        IRewardManager rewardManager = torusPool.rewardManager();

        torusPool.deposit(100 * 10**decimals, 1);
        skip(1 days);
        (uint256 torusRewards, uint256 crvRewards, uint256 cvxRewards) = rewardManager
            .claimableRewards(bb8);
        assertGt(torusRewards, 0);
        assertGt(crvRewards, 0);
        assertGt(cvxRewards, 0);

        (uint256 torusClaimed, uint256 crvClaimed, uint256 cvxClaimed) = rewardManager
            .claimEarnings();
        console.log("torusClaimed", torusClaimed);
        assertEq(torusClaimed, torusRewards);
        assertEq(crvClaimed, crvRewards);
        assertEq(cvxClaimed, cvxRewards);
    }

    function testHandleInvalidConvexPid() public {
        torusPool.addCurvePool(CurvePools.RETH_ETH_POOL);

        ITorusPool.PoolWeight[] memory newWeights = new ITorusPool.PoolWeight[](2);
        newWeights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 0.6e18);
        newWeights[1] = ITorusPool.PoolWeight(CurvePools.RETH_ETH_POOL, 0.4e18);
        skip(14 days);
        _setWeights(address(torusPool), newWeights);

        address[] memory pools = torusPool.allCurvePools();
        address curvePool = pools[0];
        vm.expectRevert("convex pool pid is shutdown");
        torusPool.handleInvalidConvexPid(curvePool);
        uint256 pid = controller.curveRegistryCache().getPid(curvePool);
        vm.mockCall(
            address(controller.curveRegistryCache().BOOSTER()),
            abi.encodeWithSelector(IBooster.poolInfo.selector, pid),
            abi.encode(
                address(0), // lpToken
                address(0), // token,
                address(0), // gauge,
                address(0), // crvRewards,
                address(0), // stash,
                true // shutdown
            )
        );

        torusPool.handleInvalidConvexPid(curvePool);
        assertEq(torusPool.getPoolWeight(curvePool), 0);
        _ensureWeightsSumTo1(torusPool);
    }

    function testHandleDepeggedPool() public {
        torusPool.addCurvePool(CurvePools.RETH_ETH_POOL);

        ITorusPool.PoolWeight[] memory newWeights = new ITorusPool.PoolWeight[](2);
        newWeights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 0.6e18);
        newWeights[1] = ITorusPool.PoolWeight(CurvePools.RETH_ETH_POOL, 0.4e18);
        skip(14 days);
        _setWeights(address(torusPool), newWeights);

        address[] memory pools = torusPool.allCurvePools();
        address curvePool = pools[0];
        vm.expectRevert("pool is not depegged");
        torusPool.handleDepeggedCurvePool(curvePool);

        address lpToken = controller.curveRegistryCache().lpToken(curvePool);
        uint256 price = controller.priceOracle().getUSDPrice(lpToken);
        vm.mockCall(
            address(controller.priceOracle()),
            abi.encodeWithSelector(IOracle.getUSDPrice.selector, lpToken),
            abi.encode((price * 95) / 100)
        );
        torusPool.handleDepeggedCurvePool(curvePool);
        assertEq(torusPool.getPoolWeight(curvePool), 0);
        _ensureWeightsSumTo1(torusPool);
    }

    function testRemovePool() public {
        skip(1 days);

        torusPool.addCurvePool(CurvePools.RETH_ETH_POOL);
        ITorusPool.PoolWeight[] memory newWeights = new ITorusPool.PoolWeight[](2);
        newWeights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 0.1e18);
        newWeights[1] = ITorusPool.PoolWeight(CurvePools.RETH_ETH_POOL, 0.9e18);
        _setWeights(address(torusPool), newWeights);

        vm.prank(bb8);
        underlying.approve(address(torusPool), 100 * 10**decimals);
        vm.prank(bb8);
        torusPool.deposit(100 * 10**decimals, 1, false);

        address[] memory pools = torusPool.allCurvePools();
        address curvePool = pools[0];

        vm.expectRevert("pool has allocated funds");
        torusPool.removeCurvePool(curvePool);

        skip(14 days);

        newWeights = new ITorusPool.PoolWeight[](2);
        newWeights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 0);
        newWeights[1] = ITorusPool.PoolWeight(CurvePools.RETH_ETH_POOL, 1e18);
        _setWeights(address(torusPool), newWeights);

        vm.prank(bb8);
        torusPool.withdraw(90 * 10**decimals, 1);

        torusPool.removeCurvePool(curvePool);
        address[] memory newPools = torusPool.allCurvePools();
        assertEq(newPools.length, pools.length - 1);
        for (uint256 i = 0; i < newPools.length; i++) {
            if (newPools[i] == curvePool) fail("pool not removed");
        }
    }

    function testRemoveAndAddPool() public {
        torusPool.addCurvePool(CurvePools.RETH_ETH_POOL);
        vm.prank(bb8);
        underlying.approve(address(torusPool), 100_000 * 10**decimals);
        vm.prank(bb8);
        torusPool.deposit(100 * 10**decimals, 1, false);
        address[] memory pools = torusPool.allCurvePools();
        address curvePool = pools[1];

        skip(14 days);

        ITorusPool.PoolWeight[] memory newWeights = new ITorusPool.PoolWeight[](2);
        newWeights[0] = ITorusPool.PoolWeight(CurvePools.STETH_ETH_POOL, 1e18);
        newWeights[1] = ITorusPool.PoolWeight(CurvePools.RETH_ETH_POOL, 0);
        _setWeights(address(torusPool), newWeights);

        vm.prank(bb8);
        torusPool.withdraw(90 * 10**decimals, 1);
        torusPool.removeCurvePool(curvePool);

        torusPool.addCurvePool(curvePool);
        address[] memory newPools = torusPool.allCurvePools();
        assertEq(newPools.length, pools.length);
        for (uint256 i = 0; i < newPools.length; i++) {
            for (uint256 j = 0; j < newPools.length; j++) {
                if (newPools[i] == pools[j]) break;
                if (j == newPools.length - 1) fail("pool not added");
            }
        }
    }

    function testSetMaxIdleCurveLpRatio() public {
        uint256 currentRatio = torusPool.maxIdleCurveLpRatio();
        vm.expectRevert("same as current");
        torusPool.setMaxIdleCurveLpRatio(currentRatio);

        vm.expectRevert("ratio exceeds upper bound");
        torusPool.setMaxIdleCurveLpRatio(0.21e18);

        torusPool.setMaxIdleCurveLpRatio(0.15e18);
        assertEq(torusPool.maxIdleCurveLpRatio(), 0.15e18);
    }

    function testUpdateDepegThreshold() public {
        vm.expectRevert("invalid depeg threshold");
        torusPool.updateDepegThreshold(0.009e18);

        vm.expectRevert("invalid depeg threshold");
        torusPool.updateDepegThreshold(0.11e18);

        torusPool.updateDepegThreshold(0.05e18);
        assertEq(torusPool.depegThreshold(), 0.05e18);
    }

    function testShutdown() public {
        vm.expectRevert("not authorized");
        torusPool.shutdownPool();

        vm.prank(bb8);
        underlying.approve(address(torusPool), 100_000 * 10**decimals);
        vm.prank(bb8);
        torusPool.deposit(100 * 10**decimals, 1, false);

        vm.prank(address(controller));
        torusPool.shutdownPool();
        assertTrue(torusPool.isShutdown());

        vm.prank(bb8);
        vm.expectRevert("pool is shutdown");
        torusPool.deposit(100 * 10**decimals, 1, false);

        uint256 balanceBeforeWithdraw = underlying.balanceOf(bb8);
        uint256 lpAmount = torusPool.lpToken().balanceOf(bb8);
        vm.prank(bb8);
        torusPool.withdraw(lpAmount, 1);
        uint256 underlyingReceived = underlying.balanceOf(bb8) - balanceBeforeWithdraw;
        assertApproxEqRel(100 * 10**decimals, underlyingReceived, 0.01e18);
    }

    function _checkAllocations() internal {
        ITorusPool.PoolWithAmount[] memory allocations = torusPool.getAllocatedUnderlying();
        uint256 totalUnderlying = torusPool.totalUnderlying();
        ITorusPool.PoolWeight[] memory weights = torusPool.getWeights();
        for (uint256 i = 0; i < allocations.length; i++) {
            uint256 expected = (totalUnderlying * weights[i].weight) / 1e18;
            assertApproxEqRel(allocations[i].amount, expected, 0.03e18);
        }
        assertLt(torusPool.computeDeviationRatio(), 0.03e18);
    }
}
