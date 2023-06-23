// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "./TorusTest.sol";
import "../interfaces/vendor/IBooster.sol";

contract TorusPoolBaseTest is TorusTest {
    Controller public controller;
    TORUSLockerV2 public locker;
    TORUSMintingRebalancingRewardsHandler public rewardsHandler;
    IInflationManager public inflationManager;
    ILpTokenStaker public lpTokenStaker;
    ITORUSToken torus;

    function setUp() public virtual override {
        super.setUp();
        _setFork(mainnetFork);
        _initializeContracts();
    }

    function _initializeContracts() internal {
        controller = _createAndInitializeController();
        inflationManager = controller.inflationManager();
        lpTokenStaker = controller.lpTokenStaker();
        torus = ITORUSToken(controller.torusToken());
        rewardsHandler = _createRebalancingRewardsHandler(controller);
        locker = _createLockerV2(controller);
    }

    function _setWeights(address pool, ITorusPool.PoolWeight[] memory weights) internal {
        IController.WeightUpdate memory weightUpdate = IController.WeightUpdate({
            torusPoolAddress: pool,
            weights: weights
        });
        controller.updateWeights(weightUpdate);
    }

    function _ensureWeightsSumTo1(ITorusPool pool) internal {
        ITorusPool.PoolWeight[] memory weights = pool.getWeights();
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i].weight;
        }
        assertEq(totalWeight, 1e18);
    }
}
