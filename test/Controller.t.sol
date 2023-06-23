// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "./TorusTest.sol";
import "../contracts/testing/MockPool.sol";

contract CurveRegistryCacheTest is TorusTest {
    Controller public controller;

    function setUp() public override {
        super.setUp();
        controller = _createAndInitializeController();
    }

    function testInitialState() public {
        assertFalse(address(controller.curveRegistryCache()) == address(0));
        assertFalse(address(controller.emergencyMinter()) == address(0));
        assertFalse(address(controller.torusToken()) == address(0));
        assertFalse(address(controller.lpTokenStaker()) == address(0));
        assertEq(controller.listPools().length, 0);
        assertEq(Ownable(address(controller.emergencyMinter())).owner(), address(this));
    }

    function testAddPool() public {
        address pool = address(_createMockPool());
        controller.addPool(pool);
        assertEq(controller.listPools().length, 1);
        assertEq(controller.listPools()[0], pool);
        assertEq(controller.listActivePools().length, 1);
        assertEq(controller.listActivePools()[0], pool);
        assertTrue(controller.isPool(pool));
        assertTrue(controller.isActivePool(pool));

        vm.expectRevert("failed to add pool");
        controller.addPool(pool);
    }

    function testShutdownPool() public {
        address pool = address(_createMockPool());
        controller.addPool(pool);
        controller.shutdownPool(pool);
        assertEq(controller.listPools().length, 1);
        assertEq(controller.listPools()[0], pool);
        assertTrue(controller.isPool(pool));
        assertFalse(controller.isActivePool(pool));
        assertTrue(ITorusPool(pool).isShutdown());
    }

    function testRemovePool() public {
        address pool = address(_createMockPool());
        vm.expectRevert("failed to remove pool");
        controller.removePool(pool);

        controller.addPool(pool);
        vm.expectRevert("shutdown the pool before removing it");
        controller.removePool(pool);

        controller.shutdownPool(pool);
        controller.removePool(pool);
        assertEq(controller.listPools().length, 0);
        assertFalse(controller.isPool(pool));
        assertFalse(controller.isActivePool(pool));
    }

    function testUpdateAllWeights() public {
        ITorusPool pool1 = _createMockPool();
        ITorusPool pool2 = _createMockPool();
        controller.addPool(address(pool1));
        controller.addPool(address(pool2));

        address curvePool1 = makeAddr("curve pool 1");
        address curvePool2 = makeAddr("curve pool 2");
        address curvePool3 = makeAddr("curve pool 3");
        address curvePool4 = makeAddr("curve pool 4");
        address curvePool5 = makeAddr("curve pool 5");
        ITorusPool.PoolWeight[] memory pool1Weights = new ITorusPool.PoolWeight[](2);
        pool1Weights[0] = ITorusPool.PoolWeight(curvePool1, 0.6e18);
        pool1Weights[1] = ITorusPool.PoolWeight(curvePool2, 0.4e18);
        ITorusPool.PoolWeight[] memory pool2Weights = new ITorusPool.PoolWeight[](3);
        pool2Weights[0] = ITorusPool.PoolWeight(curvePool3, 0.2e18);
        pool2Weights[1] = ITorusPool.PoolWeight(curvePool4, 0.7e18);
        pool2Weights[2] = ITorusPool.PoolWeight(curvePool5, 0.1e18);
        IController.WeightUpdate[] memory updates = new IController.WeightUpdate[](2);
        updates[0] = IController.WeightUpdate(address(pool1), pool1Weights);
        updates[1] = IController.WeightUpdate(address(pool2), pool2Weights);
        controller.updateAllWeights(updates);

        assertEq(pool1.getWeight(curvePool1), 0.6e18);
        assertEq(pool1.getWeight(curvePool2), 0.4e18);
        assertEq(pool2.getWeight(curvePool3), 0.2e18);
        assertEq(pool2.getWeight(curvePool4), 0.7e18);
        assertEq(pool2.getWeight(curvePool5), 0.1e18);

        vm.expectRevert("EnumerableMap: nonexistent key");
        assertEq(pool1.getWeight(curvePool3), 0);
        vm.expectRevert("EnumerableMap: nonexistent key");
        assertEq(pool2.getWeight(curvePool1), 0);

        vm.expectRevert("weight update delay not elapsed");
        controller.updateAllWeights(updates);
        skip(14 days);
        controller.updateAllWeights(updates);
    }

    function testSetConvexBooster() public {
        address booster = makeAddr("booster");
        vm.mockCall(
            address(controller.convexBooster()),
            abi.encodeWithSelector(IBooster.isShutdown.selector),
            abi.encode(false)
        );
        vm.expectRevert("current booster is not shutdown");
        controller.setConvexBooster(booster);

        vm.mockCall(
            address(controller.convexBooster()),
            abi.encodeWithSelector(IBooster.isShutdown.selector),
            abi.encode(true)
        );
        controller.setConvexBooster(booster);
        assertEq(controller.convexBooster(), booster);
    }

    function testSetCurveHandler() public {
        address handler = makeAddr("handler");
        controller.setCurveHandler(handler);
        assertEq(address(controller.curveHandler()), handler);
    }

    function testSetConvexHandler() public {
        address handler = makeAddr("handler");
        controller.setConvexHandler(handler);
        assertEq(address(controller.convexHandler()), handler);
    }

    function testSetInflationManager() public {
        address inflationManager = makeAddr("inflation manager");
        controller.setInflationManager(inflationManager);
        assertEq(address(controller.inflationManager()), inflationManager);
    }

    function testSetPriceOracle() public {
        address oracle = makeAddr("oracle");
        controller.setPriceOracle(oracle);
        assertEq(address(controller.priceOracle()), oracle);
    }

    function testSetCurveRegistryCache() public {
        address cache = makeAddr("cache");
        controller.setCurveRegistryCache(cache);
        assertEq(address(controller.curveRegistryCache()), cache);
    }

    function testSetWeightUpdateMinDelay() public {
        vm.expectRevert("delay too long");
        controller.setWeightUpdateMinDelay(32 days);
        vm.expectRevert("delay too short");
        controller.setWeightUpdateMinDelay(1 days);

        controller.setWeightUpdateMinDelay(5 days);
        assertEq(controller.weightUpdateMinDelay(), 5 days);
    }

    function testSetLpTokenStaker() public {
        ITorusPool pool1 = _createMockPool();
        ITorusPool pool2 = _createMockPool();
        controller.addPool(address(pool1));
        controller.addPool(address(pool2));
        LpTokenStaker staker = new LpTokenStaker(
            address(controller),
            ITORUSToken(controller.torusToken()),
            controller.emergencyMinter()
        );
        vm.expectRevert("lpTokenStaker already set");
        controller.setLpTokenStaker(address(staker));

        vm.prank(bb8);
        vm.expectRevert("only owner or emergencyMinter");
        controller.setLpTokenStaker(address(staker));

        skip(1 days);

        EmergencyMinter emerngencyMinter = EmergencyMinter(controller.emergencyMinter());
        emerngencyMinter.switchLpTokenStaker(address(controller.lpTokenStaker()), address(staker));

        assertEq(address(controller.lpTokenStaker()), address(staker));
        assertEq(staker.poolLastUpdated(address(pool1)), block.timestamp);
        assertEq(staker.poolLastUpdated(address(pool2)), block.timestamp);
    }

    function _createMockPool() internal returns (ITorusPool) {
        MockErc20 erc20 = new MockErc20(18);
        return new MockPool(controller, address(erc20));
    }
}
