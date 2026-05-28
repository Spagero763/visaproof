// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPassport, IIdentityRegistry, IActivityOracle} from "../src/AgentPassport.sol";

/// @dev Mock ERC 8004 identity registry. Maps agent id to its controller.
contract MockIdentityRegistry is IIdentityRegistry {
    mapping(uint256 => address) public owners;

    function setOwner(uint256 agentId, address owner) external {
        owners[agentId] = owner;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        return owners[agentId];
    }
}

/// @dev Mock activity oracle returning settable scores per agent.
contract MockActivityOracle is IActivityOracle {
    struct Score {
        uint256 volume;
        uint256 txCount;
        uint256 lastUpdated;
    }

    mapping(uint256 => Score) public scores;

    function setScore(uint256 agentId, uint256 volume, uint256 txCount) external {
        scores[agentId] = Score(volume, txCount, block.timestamp);
    }

    function getActivityScore(uint256 agentId)
        external
        view
        returns (uint256 totalVolumeCUSD, uint256 txCount, uint256 lastUpdated)
    {
        Score memory s = scores[agentId];
        return (s.volume, s.txCount, s.lastUpdated);
    }
}

contract AgentPassportTest is Test {
    AgentPassport internal passport;
    MockIdentityRegistry internal registry;
    MockActivityOracle internal oracle;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant AGENT_ID = 1234;

    event AgentRegistered(uint256 indexed agentId, address indexed controller);
    event TierUpgraded(
        uint256 indexed agentId,
        AgentPassport.Tier oldTier,
        AgentPassport.Tier newTier,
        uint256 volumeCUSD,
        uint256 txCount
    );

    function setUp() public {
        registry = new MockIdentityRegistry();
        oracle = new MockActivityOracle();
        passport = new AgentPassport(address(registry), address(oracle));

        registry.setOwner(AGENT_ID, alice);
    }

    // -----------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------

    function test_Constructor_RevertsOnZeroRegistry() public {
        vm.expectRevert(AgentPassport.ZeroAddress.selector);
        new AgentPassport(address(0), address(oracle));
    }

    function test_Constructor_RevertsOnZeroOracle() public {
        vm.expectRevert(AgentPassport.ZeroAddress.selector);
        new AgentPassport(address(registry), address(0));
    }

    function test_Constructor_SetsImmutables() public view {
        assertEq(address(passport.identityRegistry()), address(registry));
        assertEq(address(passport.activityOracle()), address(oracle));
    }

    // -----------------------------------------------------------------
    // registerAgent
    // -----------------------------------------------------------------

    function test_RegisterAgent_Succeeds() public {
        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(AGENT_ID, alice);

        vm.prank(alice);
        passport.registerAgent(AGENT_ID);

        assertTrue(passport.isRegistered(AGENT_ID));
        assertEq(uint8(passport.getTier(AGENT_ID)), uint8(AgentPassport.Tier.Tourist));

        AgentPassport.Passport memory p = passport.getPassport(AGENT_ID);
        assertTrue(p.registered);
        assertEq(uint8(p.tier), uint8(AgentPassport.Tier.Tourist));
        assertEq(p.volumeCUSD, 0);
        assertEq(p.txCount, 0);
        assertEq(p.updatedAt, block.timestamp);
    }

    function test_RegisterAgent_RevertsWhenCallerNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotAgentOwner.selector, AGENT_ID, bob));
        vm.prank(bob);
        passport.registerAgent(AGENT_ID);
    }

    function test_RegisterAgent_RevertsWhenAlreadyRegistered() public {
        vm.prank(alice);
        passport.registerAgent(AGENT_ID);

        vm.expectRevert(abi.encodeWithSelector(AgentPassport.AlreadyRegistered.selector, AGENT_ID));
        vm.prank(alice);
        passport.registerAgent(AGENT_ID);
    }

    // -----------------------------------------------------------------
    // upgradeTier
    // -----------------------------------------------------------------

    function test_UpgradeTier_TouristToWorkVisaByTxCount() public {
        _register(alice, AGENT_ID);
        oracle.setScore(AGENT_ID, 0, passport.WORK_VISA_TX_COUNT());

        vm.expectEmit(true, false, false, true);
        emit TierUpgraded(
            AGENT_ID, AgentPassport.Tier.Tourist, AgentPassport.Tier.WorkVisa, 0, passport.WORK_VISA_TX_COUNT()
        );
        passport.upgradeTier(AGENT_ID);

        assertEq(uint8(passport.getTier(AGENT_ID)), uint8(AgentPassport.Tier.WorkVisa));
    }

    function test_UpgradeTier_TouristToWorkVisaByVolume() public {
        _register(alice, AGENT_ID);
        oracle.setScore(AGENT_ID, passport.WORK_VISA_VOLUME_CUSD(), 0);

        passport.upgradeTier(AGENT_ID);
        assertEq(uint8(passport.getTier(AGENT_ID)), uint8(AgentPassport.Tier.WorkVisa));
    }

    function test_UpgradeTier_TouristToCitizenshipByTxCount() public {
        _register(alice, AGENT_ID);
        oracle.setScore(AGENT_ID, 0, passport.CITIZENSHIP_TX_COUNT());

        passport.upgradeTier(AGENT_ID);
        assertEq(uint8(passport.getTier(AGENT_ID)), uint8(AgentPassport.Tier.Citizenship));
    }

    function test_UpgradeTier_TouristToCitizenshipByVolume() public {
        _register(alice, AGENT_ID);
        oracle.setScore(AGENT_ID, passport.CITIZENSHIP_VOLUME_CUSD(), 0);

        passport.upgradeTier(AGENT_ID);
        assertEq(uint8(passport.getTier(AGENT_ID)), uint8(AgentPassport.Tier.Citizenship));
    }

    function test_UpgradeTier_UpdatesPassportRecord() public {
        _register(alice, AGENT_ID);
        oracle.setScore(AGENT_ID, 6_000e18, 1_200);

        vm.warp(block.timestamp + 1 days);
        passport.upgradeTier(AGENT_ID);

        AgentPassport.Passport memory p = passport.getPassport(AGENT_ID);
        assertEq(uint8(p.tier), uint8(AgentPassport.Tier.WorkVisa));
        assertEq(p.volumeCUSD, 6_000e18);
        assertEq(p.txCount, 1_200);
        assertEq(p.updatedAt, block.timestamp);
    }

    function test_UpgradeTier_RevertsWhenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotRegistered.selector, AGENT_ID));
        passport.upgradeTier(AGENT_ID);
    }

    function test_UpgradeTier_RevertsWhenNoUpgradeAvailable() public {
        _register(alice, AGENT_ID);
        // Score below the Work Visa floor, stays Tourist.
        oracle.setScore(AGENT_ID, 10e18, 5);

        vm.expectRevert(
            abi.encodeWithSelector(AgentPassport.NoUpgradeAvailable.selector, AGENT_ID, AgentPassport.Tier.Tourist)
        );
        passport.upgradeTier(AGENT_ID);
    }

    function test_UpgradeTier_RevertsWhenAlreadyAtComputedTier() public {
        _register(alice, AGENT_ID);
        oracle.setScore(AGENT_ID, 0, passport.WORK_VISA_TX_COUNT());
        passport.upgradeTier(AGENT_ID);

        // Same score again, no further upgrade.
        vm.expectRevert(
            abi.encodeWithSelector(AgentPassport.NoUpgradeAvailable.selector, AGENT_ID, AgentPassport.Tier.WorkVisa)
        );
        passport.upgradeTier(AGENT_ID);
    }

    function test_UpgradeTier_AllowsStepwiseClimb() public {
        _register(alice, AGENT_ID);

        oracle.setScore(AGENT_ID, 0, passport.WORK_VISA_TX_COUNT());
        passport.upgradeTier(AGENT_ID);
        assertEq(uint8(passport.getTier(AGENT_ID)), uint8(AgentPassport.Tier.WorkVisa));

        oracle.setScore(AGENT_ID, 0, passport.CITIZENSHIP_TX_COUNT());
        passport.upgradeTier(AGENT_ID);
        assertEq(uint8(passport.getTier(AGENT_ID)), uint8(AgentPassport.Tier.Citizenship));
    }

    // -----------------------------------------------------------------
    // View reverts
    // -----------------------------------------------------------------

    function test_GetTier_RevertsWhenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotRegistered.selector, AGENT_ID));
        passport.getTier(AGENT_ID);
    }

    function test_GetPassport_RevertsWhenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(AgentPassport.NotRegistered.selector, AGENT_ID));
        passport.getPassport(AGENT_ID);
    }

    // -----------------------------------------------------------------
    // previewTier
    // -----------------------------------------------------------------

    function test_PreviewTier_Tourist() public view {
        assertEq(uint8(passport.previewTier(0, 0)), uint8(AgentPassport.Tier.Tourist));
    }

    function test_PreviewTier_WorkVisa() public view {
        assertEq(uint8(passport.previewTier(0, passport.WORK_VISA_TX_COUNT())), uint8(AgentPassport.Tier.WorkVisa));
    }

    function test_PreviewTier_Citizenship() public view {
        assertEq(
            uint8(passport.previewTier(passport.CITIZENSHIP_VOLUME_CUSD(), 0)), uint8(AgentPassport.Tier.Citizenship)
        );
    }

    function testFuzz_PreviewTier_MonotonicInTxCount(uint256 txCount) public view {
        txCount = bound(txCount, 0, 1_000_000);
        AgentPassport.Tier tier = passport.previewTier(0, txCount);
        if (txCount >= passport.CITIZENSHIP_TX_COUNT()) {
            assertEq(uint8(tier), uint8(AgentPassport.Tier.Citizenship));
        } else if (txCount >= passport.WORK_VISA_TX_COUNT()) {
            assertEq(uint8(tier), uint8(AgentPassport.Tier.WorkVisa));
        } else {
            assertEq(uint8(tier), uint8(AgentPassport.Tier.Tourist));
        }
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    function _register(address controller, uint256 agentId) internal {
        vm.prank(controller);
        passport.registerAgent(agentId);
    }
}
