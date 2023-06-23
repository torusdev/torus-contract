// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "./TorusTest.sol";

contract TORUSLockerV2Test is TorusTest {
    event Locked(address indexed account, uint256 amount, uint256 unlockTime, bool relocked);

    Controller public controller;
    TORUSLockerV2 public locker;
    TORUSToken public torus;

    function setUp() public override {
        super.setUp();

        controller = _createAndInitializeController();
        torus = TORUSToken(controller.torusToken());
        locker = _createLockerV2(controller);
        torus.mint(address(bb8), 100_000e18);
        vm.prank(bb8);
        torus.approve(address(locker), 100_000e18);

    }

    function testInitialState() public {
        assertEq(address(locker.controller()), address(controller));
    }

    function testLock() public {
        vm.startPrank(bb8);
        vm.expectEmit(true, false, false, true);
        emit Locked(bb8, 1_000e18, block.timestamp + 120 days, false);
        locker.lock(1_000e18, 120 days);
        assertEq(locker.totalLocked(), 1_000e18);
        assertEq(locker.lockedBalance(bb8), 1_000e18);
        assertEq(locker.balanceOf(bb8), 1_000e18);
        assertEq(torus.balanceOf(address(locker)), 1_000e18);
        assertEq(torus.balanceOf(bb8), 99_000e18);
        TORUSLockerV2.VoteLock[] memory locks = locker.userLocks(bb8);
        assertEq(locks.length, 1);
        assertEq(locks[0].amount, 1_000e18);
        assertEq(locks[0].unlockTime, block.timestamp + 120 days);
        assertEq(locker.unlockableBalance(bb8), 0);
    }

    function testLockInvalidTime() public {
        vm.startPrank(bb8);
        vm.expectRevert("lock time invalid");
        locker.lock(1_000e18, 90 days);
        vm.expectRevert("lock time invalid");
        locker.lock(1_000e18, 365 days);
    }

    function testLockMultiple() public {
        vm.startPrank(bb8);
        locker.lock(1_000e18, 120 days);
        skip(20 days);
        locker.lock(2_000e18, 200 days);
        assertEq(locker.totalLocked(), 3_000e18);
        skip(30 days);
        locker.lock(10_000e18, 220 days);

        assertEq(locker.unlockableBalance(bb8), 0);
        assertEq(locker.totalLocked(), 13_000e18);

        TORUSLockerV2.VoteLock[] memory locks = locker.userLocks(bb8);
        assertEq(locks.length, 3);
        assertEq(locks[0].unlockTime, block.timestamp + 70 days);
        assertEq(locks[1].unlockTime, block.timestamp + 170 days);
        assertEq(locks[2].unlockTime, block.timestamp + 220 days);
    }

    function testLockMultipleWithRelock() public {
        vm.startPrank(bb8);
        locker.lock(1_000e18, 120 days);
        skip(20 days);

        locker.lock(2_000e18, 200 days, true);
        assertEq(locker.totalLocked(), 3_000e18);
        TORUSLockerV2.VoteLock[] memory locks = locker.userLocks(bb8);
        assertEq(locks.length, 1);
        assertEq(locks[0].unlockTime, block.timestamp + 200 days);

        skip(50 days);
        vm.expectRevert("cannot move the unlock time up");
        locker.lock(5_000e18, 120 days, true);
    }

    function testReceiveFees() public {
        vm.prank(bb8);
        locker.lock(1_000e18, 120 days);

        skip(20 days);
        _depositFees(10_000e18, 5_000e18);
        // alone in the locker, so should receive all fees

        (uint256 claimableCrv, uint256 claimableCvx) = locker.claimableFees(bb8);
        assertEq(claimableCrv, 10_000e18);
        assertEq(claimableCvx, 5_000e18);

        vm.prank(bb8);
        (uint256 claimedCrv, uint256 claimedCvx) = locker.claimFees();
        assertEq(claimedCrv, 10_000e18);
        assertEq(claimedCvx, 5_000e18);
    }

    function testTimeBoost() public {
        vm.startPrank(bb8);
        locker.lock(1_000e18, 120 days);
        uint256 expectedBalance = 1_000e18;
        assertEq(locker.balanceOf(bb8), expectedBalance);

        locker.lock(1_000e18, 240 days);
        expectedBalance += 1_500e18;
        assertEq(locker.balanceOf(bb8), expectedBalance);

        locker.lock(1_000e18, 180 days);
        expectedBalance += 1_250e18;
        assertEq(locker.balanceOf(bb8), expectedBalance);
    }

    function testUnlockSingle() public {
        vm.startPrank(bb8);
        locker.lock(1_000e18, 120 days);
        skip(120 days);
        uint256 balanceBefore = torus.balanceOf(bb8);
        uint256 unlocked = locker.executeAvailableUnlocks();
        assertEq(unlocked, 1_000e18);
        assertEq(torus.balanceOf(bb8) - balanceBefore, 1_000e18);
        assertEq(locker.totalLocked(), 0);
    }

    function testUnlockForSingle() public {
        vm.startPrank(bb8);
        locker.lock(1_000e18, 120 days);
        skip(120 days);
        uint256 balanceBefore = torus.balanceOf(bb8);
        uint256 unlocked = locker.executeAvailableUnlocksFor(r2);
        assertEq(unlocked, 1_000e18);
        assertEq(torus.balanceOf(r2), 1_000e18);
        assertEq(torus.balanceOf(bb8), balanceBefore);
        assertEq(locker.totalLocked(), 0);
    }

    function testUnlockForMultiple() public {
        vm.startPrank(bb8);
        locker.lock(1_000e18, 120 days);
        skip(20 days);
        locker.lock(2_000e18, 160 days);
        skip(60 days);
        locker.lock(4_000e18, 120 days);
        skip(100 days);
        uint256 balanceBefore = torus.balanceOf(bb8);
        assertEq(locker.unlockableBalance(bb8), 3_000e18);
        uint256 unlocked = locker.executeAvailableUnlocksFor(r2);
        assertEq(unlocked, 3_000e18);
        assertEq(torus.balanceOf(r2), 3_000e18);
        assertEq(torus.balanceOf(bb8), balanceBefore);
        assertEq(locker.totalLocked(), 4_000e18);
    }

    function testKick() public {
        vm.prank(bb8);
        locker.lock(1_000e18, 120 days);
        vm.startPrank(r2);

        vm.expectRevert("cannot kick this lock");
        locker.kick(bb8, 0);
        skip(130 days);

        // grace period
        vm.expectRevert("cannot kick this lock");
        locker.kick(bb8, 0);

        skip(18 days);
        uint256 balanceBB8Before = torus.balanceOf(bb8);
        uint256 balanceR2Before = torus.balanceOf(r2);
        locker.kick(bb8, 0);

        assertEq(torus.balanceOf(bb8) - balanceBB8Before, 900e18);
        assertEq(torus.balanceOf(r2) - balanceR2Before, 100e18);

        assertEq(locker.totalLocked(), 0);
        assertEq(locker.balanceOf(bb8), 0);
        assertEq(locker.unlockableBalance(bb8), 0);
        assertEq(locker.userLocks(bb8).length, 0);
    }

    function _depositFees(uint256 crvAmount, uint256 cvxAmount) public {
        MockErc20(address(locker.crv())).mintFor(c3po, crvAmount);
        MockErc20(address(locker.cvx())).mintFor(c3po, cvxAmount);

        vm.startPrank(c3po);
        locker.crv().approve(address(locker), crvAmount);
        locker.cvx().approve(address(locker), cvxAmount);
        locker.receiveFees(crvAmount, cvxAmount);
        vm.stopPrank();
    }
}
