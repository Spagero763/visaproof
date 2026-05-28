// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentVisaRegistry} from "../src/AgentVisaRegistry.sol";
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

contract AgentVisaRegistryTest is Test {
    AgentVisaRegistry internal reg;
    AgentPassport internal passport;
    MockIdentityRegistry internal identity;
    MockActivityOracle internal oracle;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant A = 1;
    uint256 internal constant B = 2;
    uint256 internal constant C = 3;

    event VisaApplied(uint256 indexed agentId, address indexed controller);
    event CapabilityAdded(uint256 indexed agentId, bytes32 indexed capabilityHash, string capability);
    event CapabilityRemoved(uint256 indexed agentId, bytes32 indexed capabilityHash, string capability);

    function setUp() public {
        identity = new MockIdentityRegistry();
        oracle = new MockActivityOracle();
        passport = new AgentPassport(address(identity), address(oracle));
        reg = new AgentVisaRegistry(address(passport), address(identity), address(oracle));

        identity.setOwner(A, alice);
        identity.setOwner(B, bob);
        identity.setOwner(C, carol);
    }

    // -----------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------

    function test_Constructor_RevertsOnZeroPassport() public {
        vm.expectRevert(AgentVisaRegistry.ZeroAddress.selector);
        new AgentVisaRegistry(address(0), address(identity), address(oracle));
    }

    function test_Constructor_RevertsOnZeroIdentity() public {
        vm.expectRevert(AgentVisaRegistry.ZeroAddress.selector);
        new AgentVisaRegistry(address(passport), address(0), address(oracle));
    }

    function test_Constructor_RevertsOnZeroOracle() public {
        vm.expectRevert(AgentVisaRegistry.ZeroAddress.selector);
        new AgentVisaRegistry(address(passport), address(identity), address(0));
    }

    function test_Constructor_SetsState() public view {
        assertEq(address(reg.passport()), address(passport));
        assertEq(address(reg.identityRegistry()), address(identity));
        assertEq(address(reg.activityOracle()), address(oracle));
    }

    // -----------------------------------------------------------------
    // applyForVisa
    // -----------------------------------------------------------------

    function test_ApplyForVisa_Succeeds() public {
        _registerPassport(alice, A);

        vm.expectEmit(true, true, false, false);
        emit VisaApplied(A, alice);

        vm.prank(alice);
        reg.applyForVisa(A);

        assertTrue(reg.hasApplied(A));
        assertEq(reg.applicantsCount(), 1);
        assertEq(reg.applicants()[0], A);
    }

    function test_ApplyForVisa_RevertsWhenNotOwner() public {
        _registerPassport(alice, A);
        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.NotAgentOwner.selector, A, bob));
        vm.prank(bob);
        reg.applyForVisa(A);
    }

    function test_ApplyForVisa_RevertsWhenPassportMissing() public {
        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.PassportNotRegistered.selector, A));
        vm.prank(alice);
        reg.applyForVisa(A);
    }

    function test_ApplyForVisa_RevertsWhenAlreadyApplied() public {
        _apply(alice, A);
        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.AlreadyApplied.selector, A));
        vm.prank(alice);
        reg.applyForVisa(A);
    }

    // -----------------------------------------------------------------
    // Capabilities
    // -----------------------------------------------------------------

    function test_SetCapability_Succeeds() public {
        _apply(alice, A);

        bytes32 capHash = keccak256(bytes("defi"));
        vm.expectEmit(true, true, false, true);
        emit CapabilityAdded(A, capHash, "defi");

        vm.prank(alice);
        reg.setCapability(A, "defi");

        string[] memory caps = reg.capabilitiesOf(A);
        assertEq(caps.length, 1);
        assertEq(caps[0], "defi");

        uint256[] memory agents = reg.getAgentsByCapability("defi");
        assertEq(agents.length, 1);
        assertEq(agents[0], A);
    }

    function test_SetCapability_RevertsWhenNotOwner() public {
        _apply(alice, A);
        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.NotAgentOwner.selector, A, bob));
        vm.prank(bob);
        reg.setCapability(A, "defi");
    }

    function test_SetCapability_RevertsWhenNotApplied() public {
        _registerPassport(alice, A);
        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.NotApplied.selector, A));
        vm.prank(alice);
        reg.setCapability(A, "defi");
    }

    function test_SetCapability_RevertsOnEmpty() public {
        _apply(alice, A);
        vm.expectRevert(AgentVisaRegistry.EmptyCapability.selector);
        vm.prank(alice);
        reg.setCapability(A, "");
    }

    function test_SetCapability_RevertsOnDuplicate() public {
        _apply(alice, A);
        vm.prank(alice);
        reg.setCapability(A, "defi");

        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.CapabilityAlreadySet.selector, A, "defi"));
        vm.prank(alice);
        reg.setCapability(A, "defi");
    }

    function test_SetCapability_MultipleAgentsSameCapability() public {
        _apply(alice, A);
        _apply(bob, B);

        vm.prank(alice);
        reg.setCapability(A, "defi");
        vm.prank(bob);
        reg.setCapability(B, "defi");

        uint256[] memory agents = reg.getAgentsByCapability("defi");
        assertEq(agents.length, 2);
        assertEq(agents[0], A);
        assertEq(agents[1], B);
    }

    function test_RemoveCapability_Succeeds() public {
        _apply(alice, A);
        vm.prank(alice);
        reg.setCapability(A, "defi");

        bytes32 capHash = keccak256(bytes("defi"));
        vm.expectEmit(true, true, false, true);
        emit CapabilityRemoved(A, capHash, "defi");

        vm.prank(alice);
        reg.removeCapability(A, "defi");

        assertEq(reg.capabilitiesOf(A).length, 0);
        assertEq(reg.getAgentsByCapability("defi").length, 0);
    }

    function test_RemoveCapability_RevertsWhenNotOwner() public {
        _apply(alice, A);
        vm.prank(alice);
        reg.setCapability(A, "defi");

        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.NotAgentOwner.selector, A, bob));
        vm.prank(bob);
        reg.removeCapability(A, "defi");
    }

    function test_RemoveCapability_RevertsWhenNotSet() public {
        _apply(alice, A);
        vm.expectRevert(abi.encodeWithSelector(AgentVisaRegistry.CapabilityNotSet.selector, A, "defi"));
        vm.prank(alice);
        reg.removeCapability(A, "defi");
    }

    function test_RemoveCapability_MiddleOfListReindexes() public {
        _apply(alice, A);
        _apply(bob, B);
        _apply(carol, C);

        vm.prank(alice);
        reg.setCapability(A, "defi");
        vm.prank(bob);
        reg.setCapability(B, "defi");
        vm.prank(carol);
        reg.setCapability(C, "defi");

        // Remove the middle agent (B); list should swap-pop to [A, C].
        vm.prank(bob);
        reg.removeCapability(B, "defi");

        uint256[] memory agents = reg.getAgentsByCapability("defi");
        assertEq(agents.length, 2);
        // Order after swap-pop: A stays at 0, C moved into B's slot.
        assertEq(agents[0], A);
        assertEq(agents[1], C);

        // Carol can still remove her own entry after the reindex.
        vm.prank(carol);
        reg.removeCapability(C, "defi");
        assertEq(reg.getAgentsByCapability("defi").length, 1);
        assertEq(reg.getAgentsByCapability("defi")[0], A);
    }

    function test_Capability_CaseSensitive() public {
        _apply(alice, A);
        vm.prank(alice);
        reg.setCapability(A, "DeFi");

        assertEq(reg.getAgentsByCapability("defi").length, 0);
        assertEq(reg.getAgentsByCapability("DeFi").length, 1);
    }

    // -----------------------------------------------------------------
    // isEligible
    // -----------------------------------------------------------------

    function test_IsEligible_TrueWhenOracleScoreReachesTier() public {
        _registerPassport(alice, A);
        oracle.setScore(A, 0, passport.WORK_VISA_TX_COUNT());

        assertTrue(reg.isEligible(A, AgentPassport.Tier.WorkVisa));
        assertFalse(reg.isEligible(A, AgentPassport.Tier.Citizenship));
    }

    function test_IsEligible_UsesLiveOracleNotCachedPassport() public {
        // Passport stays Tourist (never upgraded) but live oracle shows Citizenship.
        _registerPassport(alice, A);
        oracle.setScore(A, passport.CITIZENSHIP_VOLUME_CUSD(), 0);

        assertEq(uint8(passport.getTier(A)), uint8(AgentPassport.Tier.Tourist));
        assertTrue(reg.isEligible(A, AgentPassport.Tier.Citizenship));
    }

    function test_IsEligible_TouristAlwaysTrue() public {
        _registerPassport(alice, A);
        assertTrue(reg.isEligible(A, AgentPassport.Tier.Tourist));
    }

    // -----------------------------------------------------------------
    // getLeaderboard
    // -----------------------------------------------------------------

    function test_GetLeaderboard_EmptyWhenNoApplicants() public view {
        assertEq(reg.getLeaderboard(0, 10).length, 0);
    }

    function test_GetLeaderboard_EmptyWhenLimitZero() public {
        _apply(alice, A);
        assertEq(reg.getLeaderboard(0, 0).length, 0);
    }

    function test_GetLeaderboard_SortsByVolumeDescending() public {
        _applyWithVolume(alice, A, 1_000e18);
        _applyWithVolume(bob, B, 9_000e18);
        _applyWithVolume(carol, C, 5_000e18);

        uint256[] memory board = reg.getLeaderboard(0, 10);
        assertEq(board.length, 3);
        assertEq(board[0], B); // 9000
        assertEq(board[1], C); // 5000
        assertEq(board[2], A); // 1000
    }

    function test_GetLeaderboard_RespectsLimit() public {
        _applyWithVolume(alice, A, 1_000e18);
        _applyWithVolume(bob, B, 9_000e18);
        _applyWithVolume(carol, C, 5_000e18);

        uint256[] memory board = reg.getLeaderboard(0, 2);
        assertEq(board.length, 2);
        assertEq(board[0], B);
        assertEq(board[1], C);
    }

    function test_GetLeaderboard_FiltersByMinTier() public {
        // A reaches Work Visa, B stays Tourist, C reaches Citizenship.
        _applyAndUpgrade(alice, A, 5_000e18, 0); // WorkVisa by volume
        _apply(bob, B); // Tourist
        _applyAndUpgrade(carol, C, 15_000e18, 0); // Citizenship by volume

        uint256[] memory board = reg.getLeaderboard(uint8(AgentPassport.Tier.WorkVisa), 10);
        assertEq(board.length, 2);
        assertEq(board[0], C); // higher cached volume
        assertEq(board[1], A);
    }

    function test_GetLeaderboard_EmptyWhenNoneMeetTier() public {
        _apply(alice, A); // Tourist only
        uint256[] memory board = reg.getLeaderboard(uint8(AgentPassport.Tier.Citizenship), 10);
        assertEq(board.length, 0);
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    function _registerPassport(address controller, uint256 agentId) internal {
        vm.prank(controller);
        passport.registerAgent(agentId);
    }

    function _apply(address controller, uint256 agentId) internal {
        _registerPassport(controller, agentId);
        vm.prank(controller);
        reg.applyForVisa(agentId);
    }

    function _applyWithVolume(address controller, uint256 agentId, uint256 volume) internal {
        _apply(controller, agentId);
        // Upgrade so cached passport volume reflects the score used for sorting.
        oracle.setScore(agentId, volume, 0);
        if (volume >= passport.WORK_VISA_VOLUME_CUSD()) {
            passport.upgradeTier(agentId);
        }
    }

    function _applyAndUpgrade(address controller, uint256 agentId, uint256 volume, uint256 txCount) internal {
        _apply(controller, agentId);
        oracle.setScore(agentId, volume, txCount);
        passport.upgradeTier(agentId);
    }
}
